import 'package:equatable/equatable.dart';
import '../domain/frame_data.dart';

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

  const VideoAnalyzing(this.videoPath, this.framesProcessed);

  @override
  List<Object?> get props => [videoPath, framesProcessed];
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
  List<Object> get props => [imagePath, videoPath, mappingResult, startTimestamp, targetHeight];
}

class MidiGenerationComplete extends VideoState {
  final String midiPath;
  
  const MidiGenerationComplete(this.midiPath);

  @override
  List<Object> get props => [midiPath];
}

class VideoError extends VideoState {
  final String message;
  const VideoError(this.message);

  @override
  List<Object?> get props => [message];
}

