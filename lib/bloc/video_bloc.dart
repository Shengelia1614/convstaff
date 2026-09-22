import 'package:flutter_bloc/flutter_bloc.dart';
import '../service/video_analyzer_service.dart';
import '../service/key_mapper_service.dart';
import '../service/note_extractor_service.dart';
import 'video_event.dart';
import 'video_state.dart';

class VideoBloc extends Bloc<VideoEvent, VideoState> {
  final VideoAnalyzerService analyzerService;
  final KeyMapperService mapperService;
  final NoteExtractorService noteExtractorService;

  VideoBloc({
    required this.analyzerService,
    required this.mapperService,
    required this.noteExtractorService,
  }) : super(VideoInitial()) {
    on<VideoSelected>((event, emit) {
      emit(VideoLoaded(event.videoPath));
    });

    on<AnalyzeVideo>((event, emit) async {
      if (state is VideoLoaded ||
          state is VideoAnalysisComplete ||
          state is KeyMappingComplete ||
          state is MidiGenerationComplete) {
        String path = "";
        if (state is VideoLoaded) path = (state as VideoLoaded).videoPath;
        if (state is VideoAnalysisComplete)
          path = (state as VideoAnalysisComplete).videoPath;
        if (state is KeyMappingComplete)
          path = (state as KeyMappingComplete).videoPath;

        if (path.isEmpty) return;

        final targetHeight = event.targetHeight;
        emit(VideoAnalyzing(path, 0));

        try {
          final duration = await analyzerService.getVideoDuration(path);
          if (duration == 0)
            throw Exception("Could not determine video duration");
          print(
              'Video duration: $duration seconds (Downscale target: ${targetHeight}p)');

          String? successPath;
          Exception? lastError;

          double? firstValidT;
          KeyMappingResult? currentMapping;
          String? currentFramePath;
          
          if (event.manualStartTime != null) {
            double t = event.manualStartTime!;
            print('Manual start time provided: $t seconds. Extracting mapping...');
            final frame = await analyzerService.extractFrameAt(path, t, targetHeight: targetHeight);
            final mapping = mapperService.mapKeys(frame.path);
            firstValidT = t;
            currentMapping = mapping;
            currentFramePath = frame.path;
          } else {
            for (double t = 0; t <= duration; t += 0.1) {
              print('Testing frame at $t seconds...');
              try {
                final frame = await analyzerService.extractFrameAt(path, t,
                    targetHeight: targetHeight);
                final mapping = mapperService.mapKeys(frame.path);
                firstValidT = t;
                currentMapping = mapping;
                currentFramePath = frame.path;
                print(
                    'Keyboard detected at $t seconds (initial contrast: ${mapping.contrast})');
                break;
              } catch (e) {
                lastError = e is Exception ? e : Exception(e.toString());
                print('Frame at $t seconds invalid: ${lastError.toString()}');
                continue;
              }
            }
          }

          if (firstValidT != null &&
              currentMapping != null &&
              currentFramePath != null) {
            double finalT = firstValidT;
            KeyMappingResult finalMapping = currentMapping;
            String bestFramePath = currentFramePath;
            int prevContrast = currentMapping.contrast;
            int prevBrightness = currentMapping.brightness;
            
            if (event.manualStartTime == null) {
              bool peakSharpnessFound = false;

              for (double t = firstValidT + 0.1; t <= duration; t += 0.1) {
                try {
                  final frame = await analyzerService.extractFrameAt(path, t,
                      targetHeight: targetHeight);
                  final mapping = mapperService.mapKeys(frame.path);
                  int dContrast = mapping.contrast - prevContrast;
                  int dBrightness = mapping.brightness - prevBrightness;
                  
                  finalT = t;
                  finalMapping = mapping;
                  bestFramePath = frame.path;

                  if (!peakSharpnessFound) {
                    print('Tracking unblur at $t seconds: contrast=${mapping.contrast} (delta=+$dContrast)');
                    if (dContrast <= 5) {
                      peakSharpnessFound = true;
                      print('Exact blur end detected at $t seconds (peak contrast: ${mapping.contrast})!');
                    }
                  } 
                  
                  if (peakSharpnessFound) {
                    print('Tracking fade-in at $t seconds: brightness=${mapping.brightness} (delta=+$dBrightness)');
                    if (dBrightness <= 1000) {
                       print('Peak brightness detected at $t seconds! Fade-in complete.');
                       break;
                    }
                  }

                  prevContrast = mapping.contrast;
                  prevBrightness = mapping.brightness;
                } catch (e) {
                  break;
                }
              }
            }

            successPath =
                mapperService.drawBorders(bestFramePath, finalMapping);
            print(
                'Successfully mapped 88 keys at $finalT seconds (at peak sharpness)!');
            emit(KeyMappingComplete(
                successPath, path, finalMapping, finalT, targetHeight));
          } else {
            emit(VideoError(
                "Failed to find any valid 88-key layout in the entire video. Last error: ${lastError?.toString()}"));
          }
        } catch (e) {
          emit(VideoError(e.toString()));
        }
      }
    });

    on<GenerateMidi>((event, emit) async {
      if (state is KeyMappingComplete) {
        final currentState = state as KeyMappingComplete;
        emit(VideoAnalyzing(
            currentState.videoPath, 0)); //  reusing state for loading ui

        try {
          int extractionHeight;
          if (event.nativeResolution) {
             extractionHeight = await analyzerService.getVideoHeight(currentState.videoPath);
             if (extractionHeight == 0) {
                throw Exception("Could not determine native video height");
             }
          } else {
             extractionHeight = event.use360p ? 360 : currentState.targetHeight;
          }
          
          double scaleFactor = extractionHeight / currentState.targetHeight;
          KeyMappingResult scaledMapping =
              currentState.mappingResult.scale(scaleFactor);

          int cropHeight = 5;
          int cropY = scaledMapping.targetY - (cropHeight ~/ 2);
          if (cropY < 0) cropY = 0;
          if (cropY + cropHeight > extractionHeight) {
            cropY = extractionHeight - cropHeight;
          }
          if (cropY % 2 != 0) cropY -= 1;

          scaledMapping =
              scaledMapping.withTargetY(scaledMapping.targetY - cropY);

          print(
              'Extracting video frames starting from ${currentState.startTimestamp}s via ffmpeg (${event.nativeResolution ? 'native' : '${extractionHeight}p'}, cropped to ${cropHeight}px)...');
          final frames = analyzerService.extractFrames(
            currentState.videoPath,
            startAtSeconds: currentState.startTimestamp,
            targetHeight: event.nativeResolution ? null : extractionHeight,
            cropY: cropY,
            cropHeight: cropHeight,
            uncompressed: event.nativeResolution,
          );
          print('Processing extracted frames to find note events...');
          final notes = await noteExtractorService.extractNotes(
            frames, scaledMapping,
            detectHandSwitch: event.detectHandSwitch);

          print('Generating MIDI file with ${notes.length} notes...');
          final midiPath = await noteExtractorService.generateMidiFile(
              notes, currentState.videoPath);
          print('MIDI generation complete: $midiPath');
          emit(MidiGenerationComplete(midiPath));
        } catch (e) {
          print('Error generating MIDI: $e');
          emit(VideoError(e.toString()));
        }
      }
    });
  }
}
