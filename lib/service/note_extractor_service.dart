import 'dart:io';
import 'package:image/image.dart' as img;
import '../domain/frame_data.dart';
import 'key_mapper_service.dart';

class NoteEvent {
  final int noteIndex;
  Duration startTime;
  Duration? endTime; //  null if still pressed

  NoteEvent({
    required this.noteIndex,
    required this.startTime,
    this.endTime,
  });
}

class NoteExtractorService {
  Future<List<NoteEvent>> extractNotes(
      Stream<FrameData> frames, KeyMappingResult mapping,
      {bool detectHandSwitch = true}) async {
    List<NoteEvent> activeNotes = [];
    List<NoteEvent> completedNotes = [];

    List<int> baselineLuminance = List.filled(88, -1);
    List<int> baselineLeftLum = List.filled(88, -1);
    List<int> baselineRightLum = List.filled(88, -1);

    List<int> previousLuminance = List.filled(88, -1);

    List<bool> isPressed = List.filled(88, false);

    List<int> peakDelta = List.filled(88, 0);

    const int minWhiteDelta = 25;
    const int minBlackDelta = 45;

    const double gradientRatio = 1.25;
    const int minGradientDiff = 5;

    int frameCount = 0;

    await for (final frame in frames) {
      frameCount++;
      
      // yield to the main isolate event loop every 10 frames 
      // this guarantees the flutter ui will never freeze during extraction
      if (frameCount % 10 == 0) {
        await Future.delayed(Duration.zero);
      }
      
      if (frameCount % 100 == 0) {
        print('Processed $frameCount frames...');
      }

      final bytes = File(frame.imageFile.path).readAsBytesSync();
      final image = img.decodeImage(bytes);
      if (image == null) continue;

      List<int> currentLuminance = List.filled(88, 0);
      List<int> currentLeftLum = List.filled(88, 0);
      List<int> currentRightLum = List.filled(88, 0);

      for (int i = 0; i < 88; i++) {
        final key = mapping.keys[i];
        int sampleLeft = key.left;
        int sampleRight = key.right;

        if (key.isBlack) {
          int center = (key.left + key.right) ~/ 2;
          int halfW = ((key.right - key.left + 1) * 0.30).round();
          if (halfW < 1) halfW = 1;
          sampleLeft = center - halfW;
          sampleRight = center + halfW;
        }

        int mid = (sampleLeft + sampleRight) ~/ 2;
        int maxRawLum = 0;
        int maxRawLeft = 0;
        int maxRawRight = 0;

        for (int y = 0; y < image.height; y++) {
          int sum = 0, count = 0;
          int leftSum = 0, leftCount = 0;
          int rightSum = 0, rightCount = 0;

          for (int x = sampleLeft; x <= sampleRight; x++) {
            final pixel = image.getPixelSafe(x, y);
            int lum = (pixel.r + pixel.g + pixel.b) ~/ 3;
            sum += lum;
            count++;

            if (x <= mid) {
              leftSum += lum;
              leftCount++;
            } else {
              rightSum += lum;
              rightCount++;
            }
          }

          int rawLum = count > 0 ? sum ~/ count : 0;
          int rawLeft = leftCount > 0 ? leftSum ~/ leftCount : rawLum;
          int rawRight = rightCount > 0 ? rightSum ~/ rightCount : rawLum;

          if (rawLum > maxRawLum) maxRawLum = rawLum;
          if (rawLeft > maxRawLeft) maxRawLeft = rawLeft;
          if (rawRight > maxRawRight) maxRawRight = rawRight;
        }

        double gain =
            (i < mapping.vignetteGains.length) ? mapping.vignetteGains[i] : 1.0;
        currentLuminance[i] = (maxRawLum * gain).round().clamp(0, 255);
        currentLeftLum[i] = (maxRawLeft * gain).round().clamp(0, 255);
        currentRightLum[i] = (maxRawRight * gain).round().clamp(0, 255);
      }

      if (baselineLuminance[0] == -1) {
        for (int i = 0; i < 88; i++) {
          baselineLuminance[i] = currentLuminance[i];
          baselineLeftLum[i] = currentLeftLum[i];
          baselineRightLum[i] = currentRightLum[i];
          previousLuminance[i] = currentLuminance[i];
        }
        continue;
      }

      // GLOBAL DYNAMIC BASELINE TRACKING
      // Neutralizes video fade-ins, fade-outs, and global screen flashes.
      // We calculate the median drift of all unpressed keys and shift the baseline for all keys.
      List<int> whiteDrifts = [];
      List<int> blackDrifts = [];
      for (int i = 0; i < 88; i++) {
        if (!isPressed[i]) {
          int d = currentLuminance[i] - baselineLuminance[i];
          if (mapping.keys[i].isBlack) {
            blackDrifts.add(d);
          } else {
            whiteDrifts.add(d);
          }
        }
      }
      
      if (whiteDrifts.isNotEmpty) whiteDrifts.sort();
      if (blackDrifts.isNotEmpty) blackDrifts.sort();
      
      int whiteDriftComp = whiteDrifts.isEmpty ? 0 : whiteDrifts[whiteDrifts.length ~/ 2];
      int blackDriftComp = blackDrifts.isEmpty ? 0 : blackDrifts[blackDrifts.length ~/ 2];

      if (whiteDriftComp != 0 || blackDriftComp != 0) {
        for (int i = 0; i < 88; i++) {
          int shift = mapping.keys[i].isBlack ? blackDriftComp : whiteDriftComp;
          baselineLuminance[i] += shift;
          if (baselineLuminance[i] < 0) baselineLuminance[i] = 0;
          if (baselineLuminance[i] > 255) baselineLuminance[i] = 255;
          
          baselineLeftLum[i] += shift;
          if (baselineLeftLum[i] < 0) baselineLeftLum[i] = 0;
          if (baselineLeftLum[i] > 255) baselineLeftLum[i] = 255;
          
          baselineRightLum[i] += shift;
          if (baselineRightLum[i] < 0) baselineRightLum[i] = 0;
          if (baselineRightLum[i] > 255) baselineRightLum[i] = 255;
        }
      }

      List<bool> currentIsBleed = List.filled(88, false);
      for (int i = 0; i < 88; i++) {
        int leftHalfDelta = (currentLeftLum[i] - baselineLeftLum[i]).abs();
        int rightHalfDelta = (currentRightLum[i] - baselineRightLum[i]).abs();

        if (i > 0) {
          int leftNeighborDelta =
              (currentLuminance[i - 1] - baselineLuminance[i - 1]).abs();
          if (isPressed[i - 1] || leftNeighborDelta >= minWhiteDelta) {
            if (leftHalfDelta > rightHalfDelta * gradientRatio &&
                (leftHalfDelta - rightHalfDelta) >= minGradientDiff) {
              currentIsBleed[i] = true;
            }
          }
        }
        if (i < 87 && !currentIsBleed[i]) {
          int rightNeighborDelta =
              (currentLuminance[i + 1] - baselineLuminance[i + 1]).abs();
          if (isPressed[i + 1] || rightNeighborDelta >= minWhiteDelta) {
            if (rightHalfDelta > leftHalfDelta * gradientRatio &&
                (rightHalfDelta - leftHalfDelta) >= minGradientDiff) {
              currentIsBleed[i] = true;
            }
          }
        }
      }

      for (int i = 0; i < 88; i++) {
        if (isPressed[i]) {
          final key = mapping.keys[i];
          int currDelta = (currentLuminance[i] - baselineLuminance[i]).abs();
          if (currDelta > peakDelta[i]) peakDelta[i] = currDelta;

          int offThreshold = key.isBlack ? (minBlackDelta ~/ 2) : (minWhiteDelta ~/ 2);
          
          bool returnedToBaseline = currDelta < offThreshold;
          bool isBleed = currentIsBleed[i];
          int dropFromPeak = peakDelta[i] - currDelta;

          bool droppedSignificantly;
          if (detectHandSwitch) {
            droppedSignificantly = (dropFromPeak >= 20) && (currDelta < peakDelta[i] * 0.6);
          } else {
            droppedSignificantly = dropFromPeak >= 10;
          }

          if (returnedToBaseline || isBleed || droppedSignificantly) {
            isPressed[i] = false;
            for (var note in activeNotes) {
              if (note.noteIndex == i && note.endTime == null) {
                note.endTime = frame.timestamp;
                completedNotes.add(note);
                break;
              }
            }
            activeNotes
                .removeWhere((n) => n.noteIndex == i && n.endTime != null);
          }
        }
      }

      for (int i = 0; i < 88; i++) {
        if (isPressed[i]) continue;
        final key = mapping.keys[i];
        
        int currD = (currentLuminance[i] - baselineLuminance[i]).abs();
        int prevD = (previousLuminance[i] - baselineLuminance[i]).abs();
        int velocity = currD - prevD; //  rate of change in a single frame
        
        int minDelta = key.isBlack ? minBlackDelta : minWhiteDelta;

        bool isDarkeningOnWhite = !key.isBlack && (baselineLuminance[i] - currentLuminance[i] >= minWhiteDelta);

        if (currD < minDelta && !isDarkeningOnWhite) continue;

        if (!detectHandSwitch) {
          if (velocity <= 0) continue; 
          
          int leftD = i > 0 ? (currentLuminance[i - 1] - baselineLuminance[i - 1]).abs() : 0;
          int rightD = i < 87 ? (currentLuminance[i + 1] - baselineLuminance[i + 1]).abs() : 0;
          
          if (currD < leftD || currD < rightD) {
             continue; 
          }
          
          if (!isDarkeningOnWhite && velocity < 15) {
             continue; //  too slow a physical led turning on is an instant explosion of light
          }
        }

        if (isDarkeningOnWhite) {
          isPressed[i] = true;
          peakDelta[i] = currD;
          activeNotes.add(NoteEvent(noteIndex: i, startTime: frame.timestamp));
          continue;
        }

        bool isBleed = currentIsBleed[i];

        if (!isBleed || !detectHandSwitch) {
          isPressed[i] = true;
          peakDelta[i] = currD;
          activeNotes.add(NoteEvent(noteIndex: i, startTime: frame.timestamp));
        }
      }

      for (int i = 0; i < 88; i++) {
        previousLuminance[i] = currentLuminance[i];
      }
    }

    for (var note in activeNotes) {
      if (note.endTime == null) {
        note.endTime = note.startTime + const Duration(milliseconds: 100);
        completedNotes.add(note);
      }
    }

    completedNotes.sort((a, b) => a.startTime.compareTo(b.startTime));
    return completedNotes;
  }

  Future<String> generateMidiFile(
      List<NoteEvent> notes, String originalVideoPath) async {

    List<_MidiEvent> events = [];
    for (var note in notes) {
      int midiNote = note.noteIndex + 21;
      events.add(_MidiEvent(
          timeMs: note.startTime.inMilliseconds, note: midiNote, isOn: true));
      int endMs =
          note.endTime?.inMilliseconds ?? (note.startTime.inMilliseconds + 100);
      events.add(_MidiEvent(timeMs: endMs, note: midiNote, isOn: false));
    }

    events.sort((a, b) => a.timeMs.compareTo(b.timeMs));

    List<int> midiBytes = [];

    midiBytes.addAll([0x4D, 0x54, 0x68, 0x64]); //  mthd
    midiBytes.addAll([0x00, 0x00, 0x00, 0x06]); //  length 6 bytes
    midiBytes.addAll([0x00, 0x00]); //  format 0
    midiBytes.addAll([0x00, 0x01]); //  1 track
    midiBytes.addAll([0x01, 0xF4]); //  division 500 ticks per quarter note

    List<int> trackBytes = [];

    trackBytes.addAll([0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]);

    int currentTimeMs = 0;
    for (var ev in events) {
      int delta = ev.timeMs - currentTimeMs;
      currentTimeMs = ev.timeMs;

      trackBytes.addAll(_toVLQ(delta));

      if (ev.isOn) {
        trackBytes
            .addAll([0x90, ev.note, 100]); //  note on channel 0 velocity 100
      } else {
        trackBytes
            .addAll([0x80, ev.note, 0]); //  note off channel 0 velocity 0
      }
    }

    trackBytes.addAll([0x00, 0xFF, 0x2F, 0x00]);

    midiBytes.addAll([0x4D, 0x54, 0x72, 0x6B]); //  mtrk
    midiBytes.addAll([
      (trackBytes.length >> 24) & 0xFF,
      (trackBytes.length >> 16) & 0xFF,
      (trackBytes.length >> 8) & 0xFF,
      trackBytes.length & 0xFF
    ]);
    midiBytes.addAll(trackBytes);

    final path =
        originalVideoPath.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '_output.mid');
    File(path).writeAsBytesSync(midiBytes);
    return path;
  }

  List<int> _toVLQ(int value) {
    if (value == 0) return [0];
    List<int> bytes = [];
    int buffer = value & 0x7F;
    while ((value >>= 7) > 0) {
      buffer <<= 8;
      buffer |= 0x80;
      buffer += (value & 0x7F);
    }
    while (true) {
      bytes.add(buffer & 0xFF);
      if ((buffer & 0x80) != 0) {
        buffer >>= 8;
      } else {
        break;
      }
    }
    return bytes;
  }
}

class _MidiEvent {
  final int timeMs;
  final int note;
  final bool isOn;
  _MidiEvent({required this.timeMs, required this.note, required this.isOn});
}
