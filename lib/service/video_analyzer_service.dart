import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../domain/frame_data.dart';

class VideoAnalyzerService {
  Stream<FrameData> extractFrames(
    String videoPath, {
    double startAtSeconds = 0.0,
    int? targetHeight,
    int? cropY,
    int? cropHeight,
    bool uncompressed = false,
  }) async* {
    double fps = 30.0;

    String ffprobeCmd = 'ffprobe';
    if (Platform.isWindows) {
      const wingetFfprobe =
          r'C:\Users\sabas\AppData\Local\Microsoft\WinGet\Links\ffprobe.exe';
      if (File(wingetFfprobe).existsSync()) ffprobeCmd = wingetFfprobe;
    }
    final ffprobeRes = await Process.run(ffprobeCmd, [
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=r_frame_rate',
      '-of',
      'default=noprint_wrappers=1:nokey=1',
      videoPath,
    ]);
    if (ffprobeRes.exitCode == 0) {
      final rFrameRate = ffprobeRes.stdout.toString().trim();
      if (rFrameRate.contains('/')) {
        final parts = rFrameRate.split('/');
        if (parts.length == 2) {
          final num = double.tryParse(parts[0]);
          final den = double.tryParse(parts[1]);
          if (num != null && den != null && den != 0) {
            fps = num / den;
          }
        }
      }
    }

    final tempDir = await getTemporaryDirectory();
    final dirName = 'frames_${DateTime.now().millisecondsSinceEpoch}';
    final framesDir = Directory(p.join(tempDir.path, dirName));
    await framesDir.create();

    final ext = uncompressed ? 'png' : 'jpg';
    final outPattern = p.join(framesDir.path, 'frame_%05d.$ext');

    String ffmpegCmd = 'ffmpeg';
    if (Platform.isWindows) {
      const wingetFfmpeg =
          r'C:\Users\sabas\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe';
      if (File(wingetFfmpeg).existsSync()) ffmpegCmd = wingetFfmpeg;
    }

    String vf = '';
    if (targetHeight != null) {
      vf = 'scale=-2:$targetHeight';
    }
    if (cropY != null && cropHeight != null) {
      if (vf.isNotEmpty) vf += ',';
      vf += 'crop=iw:$cropHeight:0:$cropY';
    }
    if (vf.endsWith(',')) {
      vf = vf.substring(0, vf.length - 1);
    }

    final ffmpegArgs = <String>[
      if (startAtSeconds > 0) ...['-ss', startAtSeconds.toString()],
      '-i',
      videoPath,
      if (vf.isNotEmpty) ...['-vf', vf],
      '-r',
      fps.toString(),
      if (!uncompressed) ...['-qscale:v', '2'],
      outPattern,
    ];

    final ffmpegRes = await Process.run(ffmpegCmd, ffmpegArgs);

    if (ffmpegRes.exitCode == 0) {
      final files = framesDir.listSync().whereType<File>().toList();
      files.sort((a, b) => a.path.compareTo(b.path));

      for (int i = 0; i < files.length; i++) {
        final timeInSeconds = startAtSeconds + (i / fps);
        final duration =
            Duration(microseconds: (timeInSeconds * 1000000).round());
        yield FrameData(timestamp: duration, imageFile: files[i]);
      }
    } else {
      throw Exception(
          'Failed to extract video frames via ffmpeg: ${ffmpegRes.stderr}');
    }
  }

  Future<File> extractFrameAt(
    String videoPath,
    double timeInSeconds, {
    int targetHeight = 720,
  }) async {
    String ffmpegCmd = 'ffmpeg';
    if (Platform.isWindows) {
      const wingetFfmpeg =
          r'C:\Users\sabas\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe';
      if (File(wingetFfmpeg).existsSync()) ffmpegCmd = wingetFfmpeg;
    }

    final tempDir = await getTemporaryDirectory();
    final outPath = p.join(
        tempDir.path, 'frame_${DateTime.now().millisecondsSinceEpoch}.jpg');

    final ffmpegRes = await Process.run(ffmpegCmd, [
      '-ss',
      timeInSeconds.toString(),
      '-i',
      videoPath,
      '-vf',
      'scale=-2:$targetHeight',
      '-vframes',
      '1',
      '-qscale:v',
      '2',
      outPath,
    ]);

    if (ffmpegRes.exitCode == 0) {
      return File(outPath);
    } else {
      throw Exception('ffmpeg failed: ${ffmpegRes.stderr}');
    }
  }

  Future<double> getVideoDuration(String videoPath) async {
    String ffprobeCmd = 'ffprobe';
    if (Platform.isWindows) {
      const wingetFfprobe =
          r'C:\Users\sabas\AppData\Local\Microsoft\WinGet\Links\ffprobe.exe';
      if (File(wingetFfprobe).existsSync()) ffprobeCmd = wingetFfprobe;
    }
    final ffprobeRes = await Process.run(ffprobeCmd, [
      '-v',
      'error',
      '-show_entries',
      'format=duration',
      '-of',
      'default=noprint_wrappers=1:nokey=1',
      videoPath,
    ]);
    if (ffprobeRes.exitCode == 0) {
      return double.tryParse(ffprobeRes.stdout.toString().trim()) ?? 0.0;
    }
    return 0.0;
  }

  Future<int> getVideoHeight(String videoPath) async {
    String ffprobeCmd = 'ffprobe';
    if (Platform.isWindows) {
      const wingetFfprobe =
          r'C:\Users\sabas\AppData\Local\Microsoft\WinGet\Links\ffprobe.exe';
      if (File(wingetFfprobe).existsSync()) ffprobeCmd = wingetFfprobe;
    }
    final ffprobeRes = await Process.run(ffprobeCmd, [
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=height',
      '-of',
      'default=noprint_wrappers=1:nokey=1',
      videoPath,
    ]);
    if (ffprobeRes.exitCode == 0) {
      return int.tryParse(ffprobeRes.stdout.toString().trim()) ?? 0;
    }
    return 0;
  }

  Future<String> extractAudio(String videoPath) async {
    final tempDir = await getTemporaryDirectory();
    final audioPath = '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav';

    String ffmpegCmd = 'ffmpeg';
    if (Platform.isWindows) {
      const wingetFfmpeg =
          r'C:\Users\sabas\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe';
      if (File(wingetFfmpeg).existsSync()) ffmpegCmd = wingetFfmpeg;
    }

    final res = await Process.run(ffmpegCmd, [
      '-y',
      '-i',
      videoPath,
      '-vn',
      '-acodec',
      'pcm_s16le',
      '-ar',
      '44100',
      '-ac',
      '1', //  mono is sufficient for frequency analysis
      audioPath,
    ]);

    if (res.exitCode != 0) {
      throw Exception('Failed to extract audio: ${res.stderr}');
    }

    return audioPath;
  }

  Future<void> cleanupFrames(String dirPath) async {
    final dir = Directory(dirPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
