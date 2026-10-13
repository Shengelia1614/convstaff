import 'package:equatable/equatable.dart';
import '../domain/color_group.dart';

abstract class VideoEvent extends Equatable {
  const VideoEvent();

  @override
  List<Object?> get props => [];
}

class VideoSelected extends VideoEvent {
  final String videoPath;

  const VideoSelected(this.videoPath);

  @override
  List<Object?> get props => [videoPath];
}

class AnalyzeVideo extends VideoEvent {
  final int targetHeight;
  final double? manualStartTime;

  const AnalyzeVideo({this.targetHeight = 720, this.manualStartTime});

  @override
  List<Object?> get props => [targetHeight, manualStartTime];
}

class GenerateMidi extends VideoEvent {
  final bool use360p;
  final bool nativeResolution;
  final ExtractionMode extractionMode;

  const GenerateMidi({
    this.use360p = true,
    this.nativeResolution = false,
    this.extractionMode = ExtractionMode.monoColor,
  });

  @override
  List<Object?> get props => [use360p, nativeResolution, extractionMode];
}

class ConfirmColorSelection extends VideoEvent {
  final List<ColorGroup> selectedColors;

  const ConfirmColorSelection(this.selectedColors);

  @override
  List<Object?> get props => [selectedColors];
}
