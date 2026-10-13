import 'dart:math';

enum ExtractionMode {
  monoColor,
  duoColor,
}

class RgbColor {
  final int r;
  final int g;
  final int b;

  const RgbColor(this.r, this.g, this.b);

  double distanceTo(RgbColor other) {
    final dr = r - other.r;
    final dg = g - other.g;
    final db = b - other.b;
    return sqrt(dr * dr + dg * dg + db * db);
  }

  int distanceSquared(RgbColor other) {
    final dr = r - other.r;
    final dg = g - other.g;
    final db = b - other.b;
    return dr * dr + dg * dg + db * db;
  }

  double get brightness => 0.299 * r + 0.587 * g + 0.114 * b;

  double get saturation {
    final maxC = max(r, max(g, b));
    final minC = min(r, min(g, b));
    if (maxC == 0) return 0.0;
    return (maxC - minC) / maxC;
  }

  String get hexCode {
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RgbColor &&
          runtimeType == other.runtimeType &&
          r == other.r &&
          g == other.g &&
          b == other.b;

  @override
  int get hashCode => r.hashCode ^ g.hashCode ^ b.hashCode;

  @override
  String toString() => 'RGB($r, $g, $b)';
}

class ColorGroup {
  final int id;
  int sumR;
  int sumG;
  int sumB;
  int totalPixels;
  int frameCount;
  int blackKeyPixels;
  int whiteKeyPixels;
  final Set<int> blackKeysSeen;
  final Set<int> whiteKeysSeen;
  final Set<int> framesSeen;
  String label;

  ColorGroup({
    required this.id,
    required this.sumR,
    required this.sumG,
    required this.sumB,
    required this.totalPixels,
    required this.frameCount,
    this.blackKeyPixels = 0,
    this.whiteKeyPixels = 0,
    Set<int>? blackKeysSeen,
    Set<int>? whiteKeysSeen,
    Set<int>? framesSeen,
    this.label = '',
  })  : blackKeysSeen = blackKeysSeen ?? <int>{},
        whiteKeysSeen = whiteKeysSeen ?? <int>{},
        framesSeen = framesSeen ?? <int>{};

  RgbColor get representativeColor {
    if (totalPixels <= 0) return const RgbColor(0, 0, 0);
    return RgbColor(
      (sumR / totalPixels).round().clamp(0, 255),
      (sumG / totalPixels).round().clamp(0, 255),
      (sumB / totalPixels).round().clamp(0, 255),
    );
  }

  double get brightness => representativeColor.brightness;
  double get saturation => representativeColor.saturation;

  bool get operatesOnBothKeys {
    if (blackKeysSeen.isEmpty || whiteKeysSeen.isEmpty) return false;
    if (totalPixels <= 0) return false;
    if (blackKeyPixels == 0 && whiteKeyPixels == 0) {
      return true;
    }
    // Must have at least 1% area on both black and white keys to prevent 1-pixel edge blurs from qualifying
    final blackFraction = blackKeyPixels / totalPixels;
    final whiteFraction = whiteKeyPixels / totalPixels;
    return blackFraction >= 0.01 && whiteFraction >= 0.01;
  }

  void addObservation({
    required int r,
    required int g,
    required int b,
    required int pixelArea,
    required int frameIndex,
    required int keyIndex,
    required bool isBlackKey,
  }) {
    sumR += r * pixelArea;
    sumG += g * pixelArea;
    sumB += b * pixelArea;
    totalPixels += pixelArea;
    framesSeen.add(frameIndex);
    frameCount = framesSeen.length;

    if (isBlackKey) {
      blackKeyPixels += pixelArea;
      blackKeysSeen.add(keyIndex);
    } else {
      whiteKeyPixels += pixelArea;
      whiteKeysSeen.add(keyIndex);
    }
  }

  void mergeWith(ColorGroup other) {
    sumR += other.sumR;
    sumG += other.sumG;
    sumB += other.sumB;
    totalPixels += other.totalPixels;
    framesSeen.addAll(other.framesSeen);
    frameCount = framesSeen.length;
    blackKeyPixels += other.blackKeyPixels;
    whiteKeyPixels += other.whiteKeyPixels;
    blackKeysSeen.addAll(other.blackKeysSeen);
    whiteKeysSeen.addAll(other.whiteKeysSeen);
  }

  @override
  String toString() =>
      'ColorGroup#$id(${representativeColor.hexCode}, frames: $frameCount, pixels: $totalPixels, onBoth: $operatesOnBothKeys)';
}

class ColorAnalysisResult {
  final ColorGroup restingWhiteGroup;
  final ColorGroup restingBlackGroup;
  final List<ColorGroup> allDetectedGroups;
  final List<ColorGroup> candidateGroups;

  // Mono colour mode step details
  final int? monoMaxRecurrence;
  final double? monoThreshold;
  final List<ColorGroup> monoTopRecurringGroups;
  final List<ColorGroup> monoDiscardedByRecurrence;
  final List<ColorGroup> monoBothKeysGroups;
  final List<ColorGroup> monoSingleKeyGroups;
  final ColorGroup? monoSelectedGroup;
  final String? monoSelectionReason;

  // Duo colour mode step details
  final List<ColorGroup> duoBothKeysGroups;
  final List<ColorGroup>? duoAutoSelectedGroups;
  final bool duoNeedsUserSelection;
  final ColorGroup? duoPreselectedGroup;
  final List<ColorGroup> duoSelectionOptions;
  final int duoNeededCount;
  final String? duoSelectionReason;

  // Execution detailed logs
  final List<String> logs;

  ColorAnalysisResult({
    required this.restingWhiteGroup,
    required this.restingBlackGroup,
    required this.allDetectedGroups,
    required this.candidateGroups,
    this.monoMaxRecurrence,
    this.monoThreshold,
    this.monoTopRecurringGroups = const [],
    this.monoDiscardedByRecurrence = const [],
    this.monoBothKeysGroups = const [],
    this.monoSingleKeyGroups = const [],
    this.monoSelectedGroup,
    this.monoSelectionReason,
    this.duoBothKeysGroups = const [],
    this.duoAutoSelectedGroups,
    this.duoNeedsUserSelection = false,
    this.duoPreselectedGroup,
    this.duoSelectionOptions = const [],
    this.duoNeededCount = 0,
    this.duoSelectionReason,
    this.logs = const [],
  });
}
