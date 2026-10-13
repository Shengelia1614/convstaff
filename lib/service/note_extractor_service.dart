import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;
import '../domain/frame_data.dart';
import '../domain/color_group.dart';
import 'key_mapper_service.dart';

class NoteEvent {
  final int noteIndex;
  Duration startTime;
  Duration? endTime; // null if still pressed

  NoteEvent({
    required this.noteIndex,
    required this.startTime,
    this.endTime,
  });
}

class NoteExtractorService {
  static const double clusterTolerance = 22.0;
  static const double noteMatchTolerance = 30.0;
  static const double restingBaselineTolerance = 28.0;

  /// Pass 1: Analyzes color data across all frames without extracting note data.
  /// Identifies and discards the two resting key colors (black & white keys),
  /// then resolves target keypress color(s) according to mono/duo mode specifications.
  Future<ColorAnalysisResult> analyzeColors(
    List<FrameData> frames,
    KeyMappingResult mapping, {
    ExtractionMode mode = ExtractionMode.monoColor,
    void Function(int currentFrame, int totalFrames)? onProgress,
  }) async {
    final List<String> logs = [];

    void log(String message) {
      print(message);
      logs.add(message);
    }

    log('=================================================================');
    log('[Pass 1] STARTING COLOR DATA ANALYSIS ACROSS ALL FRAMES');
    log('Total frames to analyze: ${frames.length}');
    log('Keyboard keys: 88 keys (36 black, 52 white)');
    log('Extraction Mode: ${mode == ExtractionMode.monoColor ? "Mono Colour Mode" : "Duo Colour Mode"}');
    log('=================================================================');

    if (frames.isEmpty) {
      throw Exception('No frames provided for color analysis.');
    }

    // Step 0: Establish per-key baseline resting colors
    // Sample frames evenly distributed across the video to determine the non-pressed baseline of each key
    final int sampleStep = max(1, frames.length ~/ 40);
    final List<List<RgbColor>> keyColorSamples =
        List.generate(88, (_) => <RgbColor>[]);

    for (int fi = 0; fi < frames.length; fi += sampleStep) {
      if (keyColorSamples[0].length >= 40) break;
      final bytes = File(frames[fi].imageFile.path).readAsBytesSync();
      final image = img.decodeImage(bytes);
      if (image == null) continue;

      for (int i = 0; i < 88; i++) {
        final key = mapping.keys[i];
        final keyColor = _sampleKeyColor(image, key);
        keyColorSamples[i].add(keyColor);
      }
    }

    final List<RgbColor> keyBaselines = List.generate(88, (i) {
      final samples = keyColorSamples[i];
      if (samples.isEmpty) {
        return mapping.keys[i].isBlack
            ? const RgbColor(20, 20, 20)
            : const RgbColor(240, 240, 240);
      }
      final rList = samples.map((c) => c.r).toList()..sort();
      final gList = samples.map((c) => c.g).toList()..sort();
      final bList = samples.map((c) => c.b).toList()..sort();
      final mid = samples.length ~/ 2;
      return RgbColor(rList[mid], gList[mid], bList[mid]);
    });

    log('[Baseline] Established per-key non-pressed resting baselines for all 88 keys.');

    // Initialize resting key groups
    final ColorGroup restingWhiteGroup = ColorGroup(
      id: 1,
      sumR: 0,
      sumG: 0,
      sumB: 0,
      totalPixels: 0,
      frameCount: 0,
      label: 'Resting White Keys (Non-pressed State)',
    );

    final ColorGroup restingBlackGroup = ColorGroup(
      id: 2,
      sumR: 0,
      sumG: 0,
      sumB: 0,
      totalPixels: 0,
      frameCount: 0,
      label: 'Resting Black Keys (Non-pressed State)',
    );

    final List<ColorGroup> candidateGroups = [];
    int nextGroupId = 3;

    int frameIndex = 0;
    final int totalFrames = frames.length;

    for (final frame in frames) {
      frameIndex++;

      // Yield periodically to prevent UI freezes
      if (frameIndex % 10 == 0) {
        await Future.delayed(Duration.zero);
        onProgress?.call(frameIndex, totalFrames);
      }

      if (frameIndex % 1000 == 0) {
        log('Pass 1: Processed $frameIndex / $totalFrames frames...');
      }

      final bytes = File(frame.imageFile.path).readAsBytesSync();
      final image = img.decodeImage(bytes);
      if (image == null) continue;

      for (int i = 0; i < 88; i++) {
        final key = mapping.keys[i];
        final keyColor = _sampleKeyColor(image, key);
        final pixelArea = _getKeyPixelArea(key, image.height);
        final distFromRest = keyColor.distanceTo(keyBaselines[i]);

        if (distFromRest <= restingBaselineTolerance) {
          // Key is in its non-pressed resting state
          if (key.isBlack) {
            restingBlackGroup.addObservation(
              r: keyColor.r,
              g: keyColor.g,
              b: keyColor.b,
              pixelArea: pixelArea,
              frameIndex: frameIndex,
              keyIndex: i,
              isBlackKey: true,
            );
          } else {
            restingWhiteGroup.addObservation(
              r: keyColor.r,
              g: keyColor.g,
              b: keyColor.b,
              pixelArea: pixelArea,
              frameIndex: frameIndex,
              keyIndex: i,
              isBlackKey: false,
            );
          }
        } else {
          // Key is in an active state (pressed note, light spill, effect)
          ColorGroup? bestMatch;
          double bestDist = double.infinity;

          for (final group in candidateGroups) {
            final dist = keyColor.distanceTo(group.representativeColor);
            if (dist <= clusterTolerance && dist < bestDist) {
              bestDist = dist;
              bestMatch = group;
            }
          }

          if (bestMatch != null) {
            bestMatch.addObservation(
              r: keyColor.r,
              g: keyColor.g,
              b: keyColor.b,
              pixelArea: pixelArea,
              frameIndex: frameIndex,
              keyIndex: i,
              isBlackKey: key.isBlack,
            );
          } else {
            final newGroup = ColorGroup(
              id: nextGroupId++,
              sumR: 0,
              sumG: 0,
              sumB: 0,
              totalPixels: 0,
              frameCount: 0,
            );
            newGroup.addObservation(
              r: keyColor.r,
              g: keyColor.g,
              b: keyColor.b,
              pixelArea: pixelArea,
              frameIndex: frameIndex,
              keyIndex: i,
              isBlackKey: key.isBlack,
            );
            candidateGroups.add(newGroup);
          }
        }
      }
    }

    // Merge any candidate groups that drifted close together
    bool merged;
    do {
      merged = false;
      for (int i = 0; i < candidateGroups.length; i++) {
        for (int j = i + 1; j < candidateGroups.length; j++) {
          final dist = candidateGroups[i]
              .representativeColor
              .distanceTo(candidateGroups[j].representativeColor);
          if (dist <= clusterTolerance) {
            candidateGroups[i].mergeWith(candidateGroups[j]);
            candidateGroups.removeAt(j);
            merged = true;
            break;
          }
        }
        if (merged) break;
      }
    } while (merged);

    // Filter tiny transient noise speckles (< 3 frames) if stronger candidates exist
    if (candidateGroups.any((g) => g.frameCount >= 5)) {
      candidateGroups.removeWhere((g) => g.frameCount < 3);
    }

    log('\n=================================================================');
    log('[Step 1: RESTING KEY COLORS IDENTIFIED & DISCARDED]');
    log('Resting White Keys Group: ${restingWhiteGroup.representativeColor.hexCode} '
        'RGB(${restingWhiteGroup.representativeColor.r}, ${restingWhiteGroup.representativeColor.g}, ${restingWhiteGroup.representativeColor.b}) '
        '| Area: ${restingWhiteGroup.totalPixels} px | Frames: ${restingWhiteGroup.frameCount} (${((restingWhiteGroup.frameCount / totalFrames) * 100).toStringAsFixed(1)}%) -> [DISCARDED]');
    log('Resting Black Keys Group: ${restingBlackGroup.representativeColor.hexCode} '
        'RGB(${restingBlackGroup.representativeColor.r}, ${restingBlackGroup.representativeColor.g}, ${restingBlackGroup.representativeColor.b}) '
        '| Area: ${restingBlackGroup.totalPixels} px | Frames: ${restingBlackGroup.frameCount} (${((restingBlackGroup.frameCount / totalFrames) * 100).toStringAsFixed(1)}%) -> [DISCARDED]');
    log('All subsequent operations exclude these two resting key groups.');
    log('=================================================================');

    final List<ColorGroup> allDetectedGroups = [
      restingWhiteGroup,
      restingBlackGroup,
      ...candidateGroups,
    ];

    if (candidateGroups.isEmpty) {
      throw Exception(
          'No candidate keypress color groups detected after discarding resting keys.');
    }

    // Sort candidate groups by recurrence (frameCount) descending, then area descending
    candidateGroups.sort((a, b) {
      final fcCmp = b.frameCount.compareTo(a.frameCount);
      if (fcCmp != 0) return fcCmp;
      return b.totalPixels.compareTo(a.totalPixels);
    });

    log('\n[Step 2: CANDIDATE COLOR GROUPS (ACTIVE NOTES & SPILLS)]');
    for (int i = 0; i < candidateGroups.length; i++) {
      final g = candidateGroups[i];
      final rgb = g.representativeColor;
      final keyTypeDesc = g.operatesOnBothKeys
          ? 'BOTH (Black: ${g.blackKeysSeen.length}, White: ${g.whiteKeysSeen.length})'
          : g.blackKeysSeen.isNotEmpty
              ? 'BLACK ONLY (${g.blackKeysSeen.length} keys)'
              : 'WHITE ONLY (${g.whiteKeysSeen.length} keys)';
      log('  #${i + 1} ID:${g.id} ${rgb.hexCode} RGB(${rgb.r}, ${rgb.g}, ${rgb.b}) '
          '| Recurrence: ${g.frameCount} frames (${((g.frameCount / totalFrames) * 100).toStringAsFixed(1)}%) '
          '| Area: ${g.totalPixels} px | Keys: $keyTypeDesc');
    }

    if (mode == ExtractionMode.monoColor) {
      // MONO COLOUR MODE
      // Step 3: Both-Key Presence Filter FIRST (discard single-key light spills)
      log('\n[Step 3: MONO BOTH-KEY PRESENCE FILTER (FIRST)]');
      log('Discarding single-key light spills; retaining groups that operate on both black & white keys.');

      final List<ColorGroup> bothKeys =
          candidateGroups.where((g) => g.operatesOnBothKeys).toList();
      final List<ColorGroup> singleKeySpills =
          candidateGroups.where((g) => !g.operatesOnBothKeys).toList();

      log('Groups operating on BOTH Black & White keys: ${bothKeys.length}');
      for (final g in bothKeys) {
        log('  [PASS - BOTH KEYS] ID:${g.id} ${g.representativeColor.hexCode} '
            'RGB(${g.representativeColor.r}, ${g.representativeColor.g}, ${g.representativeColor.b}) '
            '| Recurrence: ${g.frameCount} frames | Brightness: ${g.brightness.toStringAsFixed(1)} '
            '| Black keys: ${g.blackKeysSeen.length}, White keys: ${g.whiteKeysSeen.length}');
      }

      log('Groups operating on SINGLE key type only (discarded light spills): ${singleKeySpills.length}');
      for (final g in singleKeySpills) {
        log('  [DISCARDED - SPILL] ID:${g.id} ${g.representativeColor.hexCode} '
            '(${g.blackKeysSeen.isNotEmpty ? "Black only" : "White only"}) '
            '| Recurrence: ${g.frameCount} frames | Brightness: ${g.brightness.toStringAsFixed(1)}');
      }

      final List<ColorGroup> eligiblePool =
          bothKeys.isNotEmpty ? bothKeys : candidateGroups;
      if (bothKeys.isEmpty) {
        log('  [NOTICE] No candidates operated on both keys; falling back to all candidates.');
      }

      // Step 4: Recurrence Filter with 80% Tolerance
      final int maxRecurrence = eligiblePool.map((g) => g.frameCount).reduce(max);
      final double threshold = maxRecurrence * (1.0 - 0.80); // 80% tolerance = >= 20% of max

      log('\n[Step 4: MONO 80% RECURRENCE TOLERANCE FILTER]');
      log('Max Recurrence among eligible groups = $maxRecurrence frames');
      log('80% Tolerance Cutoff Threshold = ${threshold.toStringAsFixed(1)} frames (retaining >= 20% of max)');

      final List<ColorGroup> topRecurring = [];
      final List<ColorGroup> discardedByRecurrence = [];

      for (final g in eligiblePool) {
        if (g.frameCount >= threshold) {
          topRecurring.add(g);
          final diffPct = maxRecurrence > 0
              ? (((maxRecurrence - g.frameCount) / maxRecurrence) * 100)
                  .toStringAsFixed(1)
              : '0';
          log('  [PASS - RECURRENCE] ID:${g.id} ${g.representativeColor.hexCode} (${g.frameCount} frames, -$diffPct% from max <= 80%)');
        } else {
          discardedByRecurrence.add(g);
          final diffPct = maxRecurrence > 0
              ? (((maxRecurrence - g.frameCount) / maxRecurrence) * 100)
                  .toStringAsFixed(1)
              : '0';
          log('  [DISCARDED - LOW RECURRENCE] ID:${g.id} ${g.representativeColor.hexCode} (${g.frameCount} frames, -$diffPct% from max > 80%)');
        }
      }

      // Step 5: Choose the Brightest
      topRecurring.sort((a, b) => b.brightness.compareTo(a.brightness));
      final ColorGroup monoSelected = topRecurring.first;
      final String reason =
          'Operates on both black & white keys, passed 80% recurrence filter (${monoSelected.frameCount} frames), and has highest brightness (${monoSelected.brightness.toStringAsFixed(1)}).';

      log('\n[Step 5: MONO SELECTION WINNER (BRIGHTEST)]');
      log('SELECTED: ${monoSelected.representativeColor.hexCode} '
          'RGB(${monoSelected.representativeColor.r}, ${monoSelected.representativeColor.g}, ${monoSelected.representativeColor.b}) '
          '| Brightness: ${monoSelected.brightness.toStringAsFixed(1)} | Frames: ${monoSelected.frameCount}');
      log('Reason: $reason');
      log('=================================================================\n');

      return ColorAnalysisResult(
        restingWhiteGroup: restingWhiteGroup,
        restingBlackGroup: restingBlackGroup,
        allDetectedGroups: allDetectedGroups,
        candidateGroups: candidateGroups,
        monoMaxRecurrence: maxRecurrence,
        monoThreshold: threshold,
        monoTopRecurringGroups: topRecurring,
        monoDiscardedByRecurrence: discardedByRecurrence,
        monoBothKeysGroups: bothKeys,
        monoSingleKeyGroups: singleKeySpills,
        monoSelectedGroup: monoSelected,
        monoSelectionReason: reason,
        logs: logs,
      );
    } else {
      // DUO COLOUR MODE
      final List<ColorGroup> bothKeys =
          candidateGroups.where((g) => g.operatesOnBothKeys).toList();

      bothKeys.sort((a, b) {
        final c = b.frameCount.compareTo(a.frameCount);
        if (c != 0) return c;
        return b.totalPixels.compareTo(a.totalPixels);
      });

      log('\n[Step 3: DUO KEY SPECIFICATION CHECK]');
      log('Candidate groups operating on both black & white keys: ${bothKeys.length}');
      for (final g in bothKeys) {
        log('  -> ${g.representativeColor.hexCode} (${g.frameCount} frames)');
      }

      if (bothKeys.length == 2) {
        const reason =
            'Exactly two color groups operate on both black & white keys. Automatically selected both.';
        log('\n[Step 4: DUO SELECTION] Automatically selected exactly 2 colors: '
            '${bothKeys[0].representativeColor.hexCode} & ${bothKeys[1].representativeColor.hexCode}');
        log('=================================================================\n');

        return ColorAnalysisResult(
          restingWhiteGroup: restingWhiteGroup,
          restingBlackGroup: restingBlackGroup,
          allDetectedGroups: allDetectedGroups,
          candidateGroups: candidateGroups,
          duoBothKeysGroups: bothKeys,
          duoAutoSelectedGroups: [bothKeys[0], bothKeys[1]],
          duoNeedsUserSelection: false,
          duoSelectionReason: reason,
          logs: logs,
        );
      } else if (bothKeys.length > 2) {
        const reason =
            'More than two color groups operate on both black & white keys. User selection required.';
        log('\n[Step 4: DUO SELECTION] More than 2 colors operate on both keys (${bothKeys.length}). Prompting user to select 2.');
        log('=================================================================\n');

        return ColorAnalysisResult(
          restingWhiteGroup: restingWhiteGroup,
          restingBlackGroup: restingBlackGroup,
          allDetectedGroups: allDetectedGroups,
          candidateGroups: candidateGroups,
          duoBothKeysGroups: bothKeys,
          duoNeedsUserSelection: true,
          duoSelectionOptions: bothKeys,
          duoNeededCount: 2,
          duoSelectionReason: reason,
          logs: logs,
        );
      } else if (bothKeys.length == 1) {
        final preselected = bothKeys.first;
        final options =
            candidateGroups.where((g) => g.id != preselected.id).toList();
        final reason =
            'Only 1 group operates on both keys (${preselected.representativeColor.hexCode}). Pre-selected and prompting user for 2nd color.';
        log('\n[Step 4: DUO SELECTION] 1 group operates on both keys. Pre-selecting ${preselected.representativeColor.hexCode} and prompting user for 2nd.');
        log('=================================================================\n');

        return ColorAnalysisResult(
          restingWhiteGroup: restingWhiteGroup,
          restingBlackGroup: restingBlackGroup,
          allDetectedGroups: allDetectedGroups,
          candidateGroups: candidateGroups,
          duoBothKeysGroups: bothKeys,
          duoNeedsUserSelection: true,
          duoPreselectedGroup: preselected,
          duoSelectionOptions: options,
          duoNeededCount: 1,
          duoSelectionReason: reason,
          logs: logs,
        );
      } else {
        const reason =
            'No color groups operate on both black & white keys. Prompting user to select 2 colors from candidates ordered by occurrence frequency.';
        log('\n[Step 4: DUO SELECTION] 0 groups operate on both keys. Prompting user to select 2 from all candidates.');
        log('=================================================================\n');

        return ColorAnalysisResult(
          restingWhiteGroup: restingWhiteGroup,
          restingBlackGroup: restingBlackGroup,
          allDetectedGroups: allDetectedGroups,
          candidateGroups: candidateGroups,
          duoBothKeysGroups: bothKeys,
          duoNeedsUserSelection: true,
          duoSelectionOptions: candidateGroups,
          duoNeededCount: 2,
          duoSelectionReason: reason,
          logs: logs,
        );
      }
    }
  }

  /// Pass 2: Note extraction using resolved target color group(s).
  /// Detects note presses whenever key area receives a color matching target group within tolerance,
  /// and note releases when it loses that color.
  Future<List<NoteEvent>> extractNotesWithColors(
    List<FrameData> frames,
    KeyMappingResult mapping,
    List<ColorGroup> targetColors, {
    double tolerance = noteMatchTolerance,
    void Function(int currentFrame, int totalFrames)? onProgress,
  }) async {
    final List<NoteEvent> activeNotes = [];
    final List<NoteEvent> completedNotes = [];
    final List<bool> isPressed = List.filled(88, false);

    final List<RgbColor> targetRgb =
        targetColors.map((g) => g.representativeColor).toList();

    print('\n=================================================================');
    print('[Pass 2] STARTING NOTE EXTRACTION');
    print('Target keypress colors: ${targetRgb.map((c) => "${c.hexCode} RGB(${c.r}, ${c.g}, ${c.b})").join(', ')}');
    print('Tolerance: $tolerance');
    print('=================================================================');

    int frameCount = 0;
    final int totalFrames = frames.length;

    for (final frame in frames) {
      frameCount++;

      if (frameCount % 10 == 0) {
        await Future.delayed(Duration.zero);
        onProgress?.call(frameCount, totalFrames);
      }

      if (frameCount % 1000 == 0) {
        print('Extracting notes: processed $frameCount/$totalFrames frames...');
      }

      final bytes = File(frame.imageFile.path).readAsBytesSync();
      final image = img.decodeImage(bytes);
      if (image == null) continue;

      for (int i = 0; i < 88; i++) {
        final key = mapping.keys[i];
        final keyColor = _sampleKeyColor(image, key);

        bool matchesTarget = false;
        for (final target in targetRgb) {
          if (keyColor.distanceTo(target) <= tolerance) {
            matchesTarget = true;
            break;
          }
        }

        if (matchesTarget) {
          if (!isPressed[i]) {
            isPressed[i] = true;
            activeNotes.add(NoteEvent(noteIndex: i, startTime: frame.timestamp));
          }
        } else {
          if (isPressed[i]) {
            isPressed[i] = false;
            for (var note in activeNotes) {
              if (note.noteIndex == i && note.endTime == null) {
                note.endTime = frame.timestamp;
                completedNotes.add(note);
                break;
              }
            }
            activeNotes.removeWhere((n) => n.noteIndex == i && n.endTime != null);
          }
        }
      }
    }

    // Close any notes still active at the end of the video
    for (var note in activeNotes) {
      if (note.endTime == null) {
        note.endTime = note.startTime + const Duration(milliseconds: 100);
        completedNotes.add(note);
      }
    }

    completedNotes.sort((a, b) => a.startTime.compareTo(b.startTime));
    print('[Pass 2 Complete] Extracted ${completedNotes.length} note events.');
    return completedNotes;
  }

  /// One-shot extraction method combining Pass 1 and Pass 2 for streams of frames.
  Future<List<NoteEvent>> extractNotes(
    Stream<FrameData> frames,
    KeyMappingResult mapping, {
    ExtractionMode mode = ExtractionMode.monoColor,
  }) async {
    final frameList = await frames.toList();
    final analysis = await analyzeColors(frameList, mapping, mode: mode);

    final List<ColorGroup> targetColors;
    if (mode == ExtractionMode.monoColor) {
      targetColors = [analysis.monoSelectedGroup!];
    } else {
      if (!analysis.duoNeedsUserSelection &&
          analysis.duoAutoSelectedGroups != null) {
        targetColors = analysis.duoAutoSelectedGroups!;
      } else if (analysis.duoPreselectedGroup != null) {
        targetColors = [
          analysis.duoPreselectedGroup!,
          analysis.duoSelectionOptions.first
        ];
      } else {
        targetColors = analysis.duoSelectionOptions.take(2).toList();
      }
    }

    return extractNotesWithColors(frameList, mapping, targetColors);
  }

  RgbColor _sampleKeyColor(img.Image image, KeyBorder key) {
    int sampleLeft = key.left;
    int sampleRight = key.right;

    if (key.isBlack) {
      int center = (key.left + key.right) ~/ 2;
      int halfW = ((key.right - key.left + 1) * 0.30).round();
      if (halfW < 1) halfW = 1;
      sampleLeft = center - halfW;
      sampleRight = center + halfW;
    } else {
      int w = key.right - key.left + 1;
      if (w > 4) {
        int inset = (w * 0.15).round();
        if (inset < 1) inset = 1;
        sampleLeft = key.left + inset;
        sampleRight = key.right - inset;
      }
    }

    sampleLeft = sampleLeft.clamp(0, image.width - 1);
    sampleRight = sampleRight.clamp(0, image.width - 1);

    int sumR = 0;
    int sumG = 0;
    int sumB = 0;
    int count = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = sampleLeft; x <= sampleRight; x++) {
        final p = image.getPixelSafe(x, y);
        sumR += p.r.toInt();
        sumG += p.g.toInt();
        sumB += p.b.toInt();
        count++;
      }
    }

    if (count == 0) return const RgbColor(0, 0, 0);
    return RgbColor(
      (sumR / count).round().clamp(0, 255),
      (sumG / count).round().clamp(0, 255),
      (sumB / count).round().clamp(0, 255),
    );
  }

  int _getKeyPixelArea(KeyBorder key, int height) {
    int sampleLeft = key.left;
    int sampleRight = key.right;

    if (key.isBlack) {
      int center = (key.left + key.right) ~/ 2;
      int halfW = ((key.right - key.left + 1) * 0.30).round();
      if (halfW < 1) halfW = 1;
      sampleLeft = center - halfW;
      sampleRight = center + halfW;
    } else {
      int w = key.right - key.left + 1;
      if (w > 4) {
        int inset = (w * 0.15).round();
        if (inset < 1) inset = 1;
        sampleLeft = key.left + inset;
        sampleRight = key.right - inset;
      }
    }

    return ((sampleRight - sampleLeft + 1).abs()) * height;
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

    midiBytes.addAll([0x4D, 0x54, 0x68, 0x64]); // mthd
    midiBytes.addAll([0x00, 0x00, 0x00, 0x06]); // length 6 bytes
    midiBytes.addAll([0x00, 0x00]); // format 0
    midiBytes.addAll([0x00, 0x01]); // 1 track
    midiBytes.addAll([0x01, 0xF4]); // division 500 ticks per quarter note

    List<int> trackBytes = [];

    trackBytes.addAll([0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]);

    int currentTimeMs = 0;
    for (var ev in events) {
      int delta = ev.timeMs - currentTimeMs;
      currentTimeMs = ev.timeMs;

      trackBytes.addAll(_toVLQ(delta));

      if (ev.isOn) {
        trackBytes
            .addAll([0x90, ev.note, 100]); // note on channel 0 velocity 100
      } else {
        trackBytes
            .addAll([0x80, ev.note, 0]); // note off channel 0 velocity 0
      }
    }

    trackBytes.addAll([0x00, 0xFF, 0x2F, 0x00]);

    midiBytes.addAll([0x4D, 0x54, 0x72, 0x6B]); // mtrk
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
