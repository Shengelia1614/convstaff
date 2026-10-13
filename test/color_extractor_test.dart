import 'package:flutter_test/flutter_test.dart';
import 'package:video_frame_analyzer/domain/color_group.dart';

void main() {
  group('RgbColor Tests', () {
    test('Calculates Euclidean distance and brightness correctly', () {
      const c1 = RgbColor(255, 0, 0);
      const c2 = RgbColor(255, 0, 0);
      expect(c1.distanceTo(c2), equals(0.0));

      const black = RgbColor(0, 0, 0);
      const white = RgbColor(255, 255, 255);
      expect(black.brightness, equals(0.0));
      expect(white.brightness, closeTo(255.0, 0.01));

      expect(c1.hexCode, equals('#FF0000'));
    });
  });

  group('ColorGroup and Analysis Logic Tests', () {
    test('operatesOnBothKeys correctly detects presence on both black and white keys', () {
      final group = ColorGroup(
        id: 1,
        sumR: 0,
        sumG: 0,
        sumB: 0,
        totalPixels: 0,
        frameCount: 0,
      );

      expect(group.operatesOnBothKeys, isFalse);

      group.addObservation(
        r: 0,
        g: 220,
        b: 255,
        pixelArea: 10,
        frameIndex: 1,
        keyIndex: 5,
        isBlackKey: true,
      );
      expect(group.operatesOnBothKeys, isFalse);

      group.addObservation(
        r: 0,
        g: 220,
        b: 255,
        pixelArea: 10,
        frameIndex: 1,
        keyIndex: 6,
        isBlackKey: false,
      );
      expect(group.operatesOnBothKeys, isTrue);
    });

    test('Mono Mode: Filters both key presence first, then 80% recurrence tolerance, then chooses brightest', () {
      // Resting White: huge area, appears in all frames
      final restingWhite = ColorGroup(
        id: 1,
        sumR: 240 * 100000,
        sumG: 240 * 100000,
        sumB: 240 * 100000,
        totalPixels: 100000,
        frameCount: 1000,
      );
      // Resting Black: huge area, appears in all frames
      final restingBlack = ColorGroup(
        id: 2,
        sumR: 20 * 80000,
        sumG: 20 * 80000,
        sumB: 20 * 80000,
        totalPixels: 80000,
        frameCount: 1000,
      );

      // Real keypress color: bright orange, appears in 800 frames, on both black and white keys
      final realNoteOrange = ColorGroup(
        id: 3,
        sumR: 255 * 5000,
        sumG: 140 * 5000,
        sumB: 0,
        totalPixels: 5000,
        frameCount: 800,
        blackKeysSeen: {1, 3},
        whiteKeysSeen: {2, 4},
      );

      // Impostor spill on white keys: appears in 850 frames (higher recurrence than note!), white keys only
      final spillWhite = ColorGroup(
        id: 4,
        sumR: 180 * 4000,
        sumG: 230 * 4000,
        sumB: 255 * 4000,
        totalPixels: 4000,
        frameCount: 850,
        whiteKeysSeen: {2, 4},
      );

      // Impostor spill on black keys: dark blue, appears in 750 frames, black keys only
      final spillBlack = ColorGroup(
        id: 5,
        sumR: 0,
        sumG: 60 * 3000,
        sumB: 120 * 3000,
        totalPixels: 3000,
        frameCount: 750,
        blackKeysSeen: {1, 3},
      );

      // Secondary note or dark glow on both keys: appears in 400 frames (within 80% tolerance of 800: 400 >= 160), darker
      final darkGlowBoth = ColorGroup(
        id: 6,
        sumR: 40 * 1000,
        sumG: 30 * 1000,
        sumB: 20 * 1000,
        totalPixels: 1000,
        frameCount: 400,
        blackKeysSeen: {1},
        whiteKeysSeen: {2},
      );

      // Transient speckle on both keys: appears in only 50 frames (< 20% of 800 -> discarded by 80% filter)
      final transientBoth = ColorGroup(
        id: 7,
        sumR: 255 * 100,
        sumG: 255 * 100,
        sumB: 255 * 100,
        totalPixels: 100,
        frameCount: 50,
        blackKeysSeen: {1},
        whiteKeysSeen: {2},
      );

      final allGroups = [
        restingWhite,
        restingBlack,
        realNoteOrange,
        spillWhite,
        spillBlack,
        darkGlowBoth,
        transientBoth,
      ];

      // Discard top 2 largest area (resting keys)
      allGroups.sort((a, b) => b.totalPixels.compareTo(a.totalPixels));
      final candidates = allGroups.sublist(2);
      expect(candidates.contains(restingWhite), isFalse);
      expect(candidates.contains(restingBlack), isFalse);

      // Step 1: Both Key Presence Filter FIRST
      final bothKeys = candidates.where((g) => g.operatesOnBothKeys).toList();
      expect(bothKeys.contains(spillWhite), isFalse); // Discarded!
      expect(bothKeys.contains(spillBlack), isFalse); // Discarded!
      expect(bothKeys.contains(realNoteOrange), isTrue);
      expect(bothKeys.contains(darkGlowBoth), isTrue);
      expect(bothKeys.contains(transientBoth), isTrue);

      // Step 2: 80% Recurrence Tolerance Filter
      final int maxRecurrence = bothKeys.map((g) => g.frameCount).reduce(max); // 800
      final double threshold = maxRecurrence * (1.0 - 0.80); // 160
      final topRecurring = bothKeys.where((g) => g.frameCount >= threshold).toList();

      expect(topRecurring.contains(transientBoth), isFalse); // 50 < 160 -> Discarded!
      expect(topRecurring.contains(realNoteOrange), isTrue); // 800 >= 160 -> Kept!
      expect(topRecurring.contains(darkGlowBoth), isTrue); // 400 >= 160 -> Kept!

      // Step 3: Choose the Brightest
      topRecurring.sort((a, b) => b.brightness.compareTo(a.brightness));
      final winner = topRecurring.first;

      expect(winner.id, equals(realNoteOrange.id)); // Orange is brightest!
    });

    test('Mono Mode Fallback: selects highest brightness when all groups are single-key-type only', () {
      final groupDark = ColorGroup(
        id: 1,
        sumR: 30 * 100,
        sumG: 30 * 100,
        sumB: 30 * 100,
        totalPixels: 100,
        frameCount: 500,
        blackKeysSeen: {1},
      );
      final groupBright = ColorGroup(
        id: 2,
        sumR: 255 * 100,
        sumG: 250 * 100,
        sumB: 200 * 100,
        totalPixels: 100,
        frameCount: 490,
        whiteKeysSeen: {2},
      );

      final candidates = [groupDark, groupBright];
      final bothKeys = candidates.where((g) => g.operatesOnBothKeys).toList();
      expect(bothKeys, isEmpty);

      candidates.sort((a, b) => b.brightness.compareTo(a.brightness));
      expect(candidates.first.id, equals(groupBright.id));
    });

    test('Duo Mode: Automatically selects when exactly 2 groups operate on both keys', () {
      final note1 = ColorGroup(
        id: 1,
        sumR: 0,
        sumG: 2000,
        sumB: 2000,
        totalPixels: 200,
        frameCount: 500,
        blackKeysSeen: {1},
        whiteKeysSeen: {2},
      );
      final note2 = ColorGroup(
        id: 2,
        sumR: 2000,
        sumG: 0,
        sumB: 2000,
        totalPixels: 200,
        frameCount: 450,
        blackKeysSeen: {3},
        whiteKeysSeen: {4},
      );
      final spill = ColorGroup(
        id: 3,
        sumR: 0,
        sumG: 500,
        sumB: 500,
        totalPixels: 100,
        frameCount: 400,
        blackKeysSeen: {1}, // black only
      );

      final candidates = [note1, note2, spill];
      final bothKeys = candidates.where((g) => g.operatesOnBothKeys).toList();

      expect(bothKeys.length, equals(2));
      expect(bothKeys.map((g) => g.id), containsAll([1, 2]));
    });

    test('Duo Mode: When 1 operates on both, auto-selects it and options contains rest', () {
      final note1 = ColorGroup(
        id: 1,
        sumR: 0,
        sumG: 2000,
        sumB: 2000,
        totalPixels: 200,
        frameCount: 500,
        blackKeysSeen: {1},
        whiteKeysSeen: {2},
      );
      final cand2 = ColorGroup(
        id: 2,
        sumR: 2000,
        sumG: 0,
        sumB: 0,
        totalPixels: 200,
        frameCount: 450,
        whiteKeysSeen: {4},
      );
      final cand3 = ColorGroup(
        id: 3,
        sumR: 0,
        sumG: 2000,
        sumB: 0,
        totalPixels: 150,
        frameCount: 300,
        blackKeysSeen: {5},
      );

      final candidates = [note1, cand2, cand3];
      final bothKeys = candidates.where((g) => g.operatesOnBothKeys).toList();

      expect(bothKeys.length, equals(1));
      final preselected = bothKeys.first;
      final options = candidates.where((g) => g.id != preselected.id).toList();

      expect(preselected.id, equals(1));
      expect(options.length, equals(2));
      expect(options.map((g) => g.id), containsAll([2, 3]));
    });
  });
}

