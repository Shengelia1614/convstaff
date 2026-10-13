import 'package:equatable/equatable.dart';
import '../domain/frame_data.dart';
import '../domain/color_group.dart';

abstract class VideoState extends Equatable {
  const VideoState();

  @override
  List<Object?> get props => [];
}

class VideoInitial extends VideoState {}

class VideoLoaded extends VideoState {
  final String videoPath;
  const VideoLoaded(this.videoPath);

  @override
  List<Object?> get props => [videoPath];
}

class VideoAnalyzing extends VideoState {
  final String videoPath;
  final int framesProcessed;
  final String? message;

  const VideoAnalyzing(this.videoPath, this.framesProcessed, [this.message]);

  @override
  List<Object?> get props => [videoPath, framesProcessed, message];
}

class VideoAnalysisComplete extends VideoState {
  final String videoPath;
  final List<FrameData> frames;

  const VideoAnalysisComplete(this.videoPath, this.frames);

  @override
  List<Object?> get props => [videoPath, frames];
}

class KeyMappingComplete extends VideoState {
  final String imagePath;
  final String videoPath;
  final dynamic mappingResult;
  final double startTimestamp;
  final int targetHeight;

  const KeyMappingComplete(
    this.imagePath,
    this.videoPath,
    this.mappingResult, [
    this.startTimestamp = 0.0,
    this.targetHeight = 720,
  ]);

  @override
  List<Object?> get props =>
      [imagePath, videoPath, mappingResult, startTimestamp, targetHeight];
}

class ColorSelectionRequired extends VideoState {
  final String videoPath;
  final List<FrameData> frames;
  final dynamic mappingResult;
  final ColorAnalysisResult analysisResult;
  final ColorGroup? preselectedGroup;
  final List<ColorGroup> selectionOptions;
  final int neededCount;

  const ColorSelectionRequired({
    required this.videoPath,
    required this.frames,
    required this.mappingResult,
    required this.analysisResult,
    this.preselectedGroup,
    required this.selectionOptions,
    required this.neededCount,
  });

  @override
  List<Object?> get props => [
        videoPath,
        frames,
        mappingResult,
        analysisResult,
        preselectedGroup,
        selectionOptions,
        neededCount,
      ];
}

class MidiGenerationComplete extends VideoState {
  final String midiPath;
  final List<ColorGroup>? detectedColors;
  final ColorAnalysisResult? analysisResult;

  const MidiGenerationComplete(this.midiPath,
      [this.detectedColors, this.analysisResult]);

  @override
  List<Object?> get props => [midiPath, detectedColors, analysisResult];
}

class VideoError extends VideoState {
  final String message;
  const VideoError(this.message);

  @override
  List<Object?> get props => [message];
}
