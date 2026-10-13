import 'dart:io';
import 'package:image/image.dart' as img;

class KeyBorder {
  final int noteIndex; //  0 for a0 87 for c8
  final int left;
  final int right;
  final bool isBlack;

  KeyBorder({
    required this.noteIndex,
    required this.left,
    required this.right,
    required this.isBlack,
  });

  @override
  String toString() {
    return 'KeyBorder(note: $noteIndex, type: ${isBlack ? "Black" : "White"}, bounds: [$left, $right])';
  }
}

class KeyMappingResult {
  final List<KeyBorder> keys;
  final int targetY;
  final int contrast;
  final int brightness;
  final List<double> vignetteGains;

  KeyMappingResult(this.keys, this.targetY,
      [this.contrast = 0, this.brightness = 0, List<double>? vignetteGains])
      : vignetteGains = vignetteGains ?? List.filled(keys.length, 1.0);

  KeyMappingResult scale(double factor) {
    List<KeyBorder> scaledKeys = keys
        .map((k) => KeyBorder(
              noteIndex: k.noteIndex,
              left: (k.left * factor).round(),
              right: (k.right * factor).round(),
              isBlack: k.isBlack,
            ))
        .toList();
    return KeyMappingResult(
      scaledKeys,
      (targetY * factor).round(),
      contrast,
      brightness,
      vignetteGains,
    );
  }

  KeyMappingResult withTargetY(int newTargetY) {
    return KeyMappingResult(keys, newTargetY, contrast, brightness, vignetteGains);
  }
}

class KeyMapperService {
  KeyMappingResult mapKeys(String imagePath) {
    final bytes = File(imagePath).readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception("Could not decode image at $imagePath");

    final width = image.width;
    final height = image.height;
    final double defaultKeyW = width / 52.0;

    int yStart = (height * 0.80).toInt();
    int yEnd = height - 5;
    List<double> colMax = List.filled(width, 0.0);
    for (int x = 0; x < width; x++) {
      double m = 0;
      for (int y = yStart; y <= yEnd; y++) {
        final p = image.getPixelSafe(x, y);
        double lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        if (lum > m) m = lum;
      }
      colMax[x] = m;
    }

    int window = (defaultKeyW * 2.2).round();
    List<double> envelope = List.filled(width, 0.0);
    for (int x = 0; x < width; x++) {
      double m = 0;
      int start = (x - window ~/ 2).clamp(0, width - 1);
      int end = (x + window ~/ 2).clamp(0, width - 1);
      for (int k = start; k <= end; k++) {
        if (colMax[k] > m) m = colMax[k];
      }
      envelope[x] = m;
    }

    List<double> smoothEnv = List.filled(width, 0.0);
    for (int x = 0; x < width; x++) {
      double sum = 0;
      int count = 0;
      int start = (x - window ~/ 2).clamp(0, width - 1);
      int end = (x + window ~/ 2).clamp(0, width - 1);
      for (int k = start; k <= end; k++) {
        sum += envelope[k];
        count++;
      }
      smoothEnv[x] = sum / count;
    }

    double targetPeak = smoothEnv[width ~/ 2];
    if (targetPeak < 100) {
      targetPeak = smoothEnv.reduce((a, b) => a > b ? a : b);
    }
    if (targetPeak < 80) targetPeak = 150;

    int bestY = 0;
    int maxScore = -1;
    List<int> bestBinary = [];

    for (int y = (height * 0.86).toInt();
        y >= (height * 0.65).toInt();
        y -= 2) {
      List<int> normalized = List.filled(width, 0);
      for (int x = 0; x < width; x++) {
        final p = image.getPixelSafe(x, y);
        double lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        double envVal = smoothEnv[x];
        double gain = targetPeak / (envVal < 15.0 ? 15.0 : envVal);
        if (gain > 5.0) gain = 5.0;
        normalized[x] = (lum * gain).round().clamp(0, 255);
      }

      int threshold = 80;
      List<int> binary = List.filled(width, 0);
      for (int x = 0; x < width; x++) {
        binary[x] = normalized[x] >= threshold ? 1 : 0;
      }

      int bigBars = 0;
      int thinLines = 0;
      int? curStart;
      for (int x = 0; x < width; x++) {
        if (binary[x] == 0) {
          curStart ??= x;
        } else {
          if (curStart != null) {
            int w = x - curStart;
            if (curStart > 10 && x < width - 10) {
              if (w >= 8 && w <= 25)
                bigBars++;
              else if (w <= 4) thinLines++;
            }
            curStart = null;
          }
        }
      }

      int score = (bigBars == 36 ? 1000 : 0) + bigBars * 10 + thinLines;
      if (score > maxScore) {
        maxScore = score;
        bestY = y;
        bestBinary = binary;
        if (bigBars == 36 && thinLines == 15) break;
      }
    }

    if (maxScore < 0) {
      throw Exception("Frame is blurry or keyboard is not yet visible.");
    }

    List<Map<String, int>> blackSegments = [];
    int? curStart;
    for (int x = 0; x < width; x++) {
      if (bestBinary[x] == 0) {
        curStart ??= x;
      } else {
        if (curStart != null) {
          blackSegments
              .add({'start': curStart, 'end': x - 1, 'width': x - curStart});
          curStart = null;
        }
      }
    }
    if (curStart != null)
      blackSegments.add(
          {'start': curStart, 'end': width - 1, 'width': width - curStart});

    List<Map<String, int>> blackKeys = [];
    List<Map<String, int>> thinSlits = [];
    for (var s in blackSegments) {
      if (s['start']! <= 12 || s['end']! >= width - 12)
        continue; //  outer margin
      if (s['width']! >= 8 && s['width']! <= 25) {
        blackKeys.add(s);
      } else if (s['width']! <= 4) {
        thinSlits.add(s);
      }
    }

    if (blackKeys.length != 36) {
      throw Exception("Found ${blackKeys.length} black keys instead of 36.");
    }

    int? findSlitBetween(int x1, int x2) {
      for (var slit in thinSlits) {
        int slitCenter = (slit['start']! + slit['end']!) ~/ 2;
        if (slitCenter >= x1 && slitCenter <= x2) {
          return slitCenter;
        }
      }
      return null;
    }

    double avgKeyW =
        (blackKeys.last['end']! - blackKeys.first['start']!) / 50.0;
    int keyboardLeft =
        (blackKeys.first['start']! - avgKeyW * 0.9).round().clamp(0, width - 1);

    List<KeyBorder> keys = [];
    int blackIdx = 0;

    keys.add(KeyBorder(
        noteIndex: 0,
        left: keyboardLeft,
        right: blackKeys[0]['start']! - 1,
        isBlack: false));

    keys.add(KeyBorder(
        noteIndex: 1,
        left: blackKeys[0]['start']!,
        right: blackKeys[0]['end']!,
        isBlack: true));
    blackIdx = 1;

    int b0Left = blackKeys[0]['end']! + 1;
    int c1Right = blackKeys[1]['start']! - 1;
    int? bcSlit = findSlitBetween(b0Left, c1Right);
    int bcDiv = bcSlit ?? ((b0Left + c1Right) ~/ 2);

    keys.add(
        KeyBorder(noteIndex: 2, left: b0Left, right: bcDiv, isBlack: false));
    keys.add(KeyBorder(
        noteIndex: 3, left: bcDiv + 1, right: c1Right, isBlack: false));

    for (int octave = 1; octave <= 7; octave++) {
      var cSharp = blackKeys[blackIdx++];
      keys.add(KeyBorder(
          noteIndex: keys.length,
          left: cSharp['start']!,
          right: cSharp['end']!,
          isBlack: true));

      var dSharp = blackKeys[blackIdx++];
      keys.add(KeyBorder(
          noteIndex: keys.length,
          left: cSharp['end']! + 1,
          right: dSharp['start']! - 1,
          isBlack: false));

      keys.add(KeyBorder(
          noteIndex: keys.length,
          left: dSharp['start']!,
          right: dSharp['end']!,
          isBlack: true));

      var fSharp = blackKeys[blackIdx];
      int eLeft = dSharp['end']! + 1;
      int fRight = fSharp['start']! - 1;
      int? efSlit = findSlitBetween(eLeft, fRight);
      int efDiv = efSlit ?? ((eLeft + fRight) ~/ 2);

      keys.add(KeyBorder(
          noteIndex: keys.length, left: eLeft, right: efDiv, isBlack: false));
      keys.add(KeyBorder(
          noteIndex: keys.length,
          left: efDiv + 1,
          right: fRight,
          isBlack: false));

      blackIdx++;
      keys.add(KeyBorder(
          noteIndex: keys.length,
          left: fSharp['start']!,
          right: fSharp['end']!,
          isBlack: true));

      var gSharp = blackKeys[blackIdx++];
      keys.add(KeyBorder(
          noteIndex: keys.length,
          left: fSharp['end']! + 1,
          right: gSharp['start']! - 1,
          isBlack: false));

      keys.add(KeyBorder(
          noteIndex: keys.length,
          left: gSharp['start']!,
          right: gSharp['end']!,
          isBlack: true));

      var aSharp = blackKeys[blackIdx++];
      keys.add(KeyBorder(
          noteIndex: keys.length,
          left: gSharp['end']! + 1,
          right: aSharp['start']! - 1,
          isBlack: false));

      keys.add(KeyBorder(
          noteIndex: keys.length,
          left: aSharp['start']!,
          right: aSharp['end']!,
          isBlack: true));

      if (octave < 7) {
        var nextCSharp = blackKeys[blackIdx];
        int bLeft = aSharp['end']! + 1;
        int nextCRight = nextCSharp['start']! - 1;
        int? nextBcSlit = findSlitBetween(bLeft, nextCRight);
        int nextBcDiv = nextBcSlit ?? ((bLeft + nextCRight) ~/ 2);

        keys.add(KeyBorder(
            noteIndex: keys.length,
            left: bLeft,
            right: nextBcDiv,
            isBlack: false));
        keys.add(KeyBorder(
            noteIndex: keys.length,
            left: nextBcDiv + 1,
            right: nextCRight,
            isBlack: false));
      } else {
        int bLeft = aSharp['end']! + 1;
        int expectedDivider = bLeft + (avgKeyW * 0.55).round();
        int? finalBcSlit =
            findSlitBetween(bLeft, bLeft + (avgKeyW * 0.9).round());
        int finalBcDiv = finalBcSlit ?? expectedDivider;

        int c8Right = (finalBcDiv + avgKeyW * 0.9).round().clamp(0, width - 1);
        int? c8OuterSlit = findSlitBetween(finalBcDiv + 5, width - 1);
        if (c8OuterSlit != null) c8Right = c8OuterSlit;

        keys.add(KeyBorder(
            noteIndex: keys.length,
            left: bLeft,
            right: finalBcDiv,
            isBlack: false));
        keys.add(KeyBorder(
            noteIndex: keys.length,
            left: finalBcDiv + 1,
            right: c8Right,
            isBlack: false));
      }
    }

    if (keys.length != 88) {
      throw Exception("Expected 88 keys, but mapped ${keys.length}");
    }

    List<double> vignetteGains = List.filled(88, 1.0);
    for (int i = 0; i < 88; i++) {
      int center = (keys[i].left + keys[i].right) ~/ 2;
      double envVal = smoothEnv[center.clamp(0, width - 1)];
      double gain = targetPeak / (envVal < 15.0 ? 15.0 : envVal);
      if (gain > 5.0) gain = 5.0;
      if (gain < 1.0) gain = 1.0;
      vignetteGains[i] = gain;
    }

    int totalBrightness = 0;
    for (int x = 0; x < width; x++) {
      final p = image.getPixelSafe(x, bestY);
      totalBrightness += ((p.r + p.g + p.b) ~/ 3).toInt();
    }

    return KeyMappingResult(keys, bestY, maxScore, totalBrightness, vignetteGains);
  }

  String drawBorders(String imagePath, KeyMappingResult mapping) {
    final bytes = File(imagePath).readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception("Could not decode image at $imagePath");

    for (var key in mapping.keys) {
      final color =
          key.isBlack ? img.ColorRgb8(255, 0, 0) : img.ColorRgb8(0, 255, 0);

      img.drawLine(image,
          x1: key.left,
          y1: 0,
          x2: key.left,
          y2: image.height - 1,
          color: color,
          thickness: 2);

      img.drawLine(image,
          x1: key.right,
          y1: 0,
          x2: key.right,
          y2: image.height - 1,
          color: color,
          thickness: 2);

      int center = (key.left + key.right) ~/ 2;
      img.drawString(image, '${key.noteIndex}',
          font: img.arial14,
          x: center - 5,
          y: image.height - 30,
          color: img.ColorRgb8(0, 0, 255));
    }

    img.drawLine(image,
        x1: 0,
        y1: mapping.targetY,
        x2: image.width - 1,
        y2: mapping.targetY,
        color: img.ColorRgb8(255, 255, 0),
        thickness: 3);

    final outPath = imagePath
        .replaceFirst('.jpg', '_annotated.jpg')
        .replaceFirst('.png', '_annotated.png');
    File(outPath).writeAsBytesSync(img.encodeJpg(image));
    return outPath;
  }
}
