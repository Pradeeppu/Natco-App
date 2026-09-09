/// Tests for the calibratable scanner thresholds.
///
/// Requirement section 19 requires these to be configurable. That makes a bad
/// configuration document a real risk: an inverted threshold set would
/// silently reclassify every answer on every sheet. So the tests here are
/// mostly about rejecting configurations rather than accepting them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/app/config/scanner_thresholds.dart';

void main() {
  group('BubbleThresholds defaults', () {
    test('are internally consistent', () {
      expect(const BubbleThresholds().isConsistent, isTrue);
    });

    test('order the thresholds so each label is reachable', () {
      const BubbleThresholds t = BubbleThresholds();
      expect(t.blankThreshold, lessThan(t.filledThreshold));
      expect(t.filledThreshold, lessThanOrEqualTo(t.multipleMarkThreshold));
      expect(t.ambiguousMargin, lessThan(t.clearMargin));
    });

    test('combine the two fill measures as a convex combination', () {
      expect(const BubbleThresholds().hasValidWeights, isTrue);
    });
  });

  group('BubbleThresholds validation', () {
    test('rejects an inverted blank and filled pair', () {
      expect(
        const BubbleThresholds(
          blankThreshold: 0.6,
          filledThreshold: 0.2,
        ).isConsistent,
        isFalse,
      );
    });

    test('rejects an ambiguous margin wider than the clear margin', () {
      expect(
        const BubbleThresholds(
          clearMargin: 0.1,
          ambiguousMargin: 0.4,
        ).isConsistent,
        isFalse,
      );
    });

    test('rejects fill weights that do not sum to one', () {
      expect(
        const BubbleThresholds(
          meanInkWeight: 0.8,
          coverageWeight: 0.8,
        ).isConsistent,
        isFalse,
      );
    });

    test('rejects a zero or negative blank threshold', () {
      expect(const BubbleThresholds(blankThreshold: 0).isConsistent, isFalse);
    });

    test('rejects a sampling diameter outside (0, 1]', () {
      expect(
        const BubbleThresholds(samplingDiameterRatio: 0).isConsistent,
        isFalse,
      );
      expect(
        const BubbleThresholds(samplingDiameterRatio: 1.4).isConsistent,
        isFalse,
      );
    });
  });

  group('ConfidenceWeights', () {
    test('defaults are consistent and sum to one', () {
      expect(const ConfidenceWeights().isConsistent, isTrue);
      expect(const ConfidenceWeights().hasValidWeights, isTrue);
    });

    test('rejects an inverted medium and high floor', () {
      expect(
        const ConfidenceWeights(
          mediumConfidenceFloor: 0.9,
          highConfidenceFloor: 0.5,
        ).isConsistent,
        isFalse,
      );
    });

    test('scores a clear single mark high', () {
      // The worked example from requirement section 18: B at 0.91 against a
      // runner-up of 0.12.
      const ConfidenceWeights weights = ConfidenceWeights();
      final double confidence = weights.score(
        topScore: 0.91,
        runnerUpScore: 0.12,
        imageQualityScore: 0.9,
      );
      expect(confidence, greaterThan(weights.highConfidenceFloor));
    });

    test('scores an ambiguous pair low', () {
      // A at 0.72 against B at 0.69 — the case that must reach a human.
      const ConfidenceWeights weights = ConfidenceWeights();
      final double confidence = weights.score(
        topScore: 0.72,
        runnerUpScore: 0.69,
        imageQualityScore: 0.9,
      );
      expect(confidence, lessThan(weights.mediumConfidenceFloor));
    });

    test('penalises an identical reading taken from a poor photograph', () {
      // Requirement section 19's intent: the same bubble pattern read off a
      // shadowed, blurry photo deserves less confidence.
      const ConfidenceWeights weights = ConfidenceWeights();
      final double clean = weights.score(
        topScore: 0.8,
        runnerUpScore: 0.1,
        imageQualityScore: 1.0,
      );
      final double poor = weights.score(
        topScore: 0.8,
        runnerUpScore: 0.1,
        imageQualityScore: 0.2,
      );
      expect(poor, lessThan(clean));
    });

    test('stays within 0.0 and 1.0 for extreme inputs', () {
      const ConfidenceWeights weights = ConfidenceWeights();
      expect(
        weights.score(topScore: 5, runnerUpScore: -5, imageQualityScore: 9),
        1.0,
      );
      expect(
        weights.score(topScore: 0, runnerUpScore: 0, imageQualityScore: 0),
        0.0,
      );
    });

    test('does not divide by zero on an all-blank question', () {
      expect(
        () => const ConfidenceWeights().score(
          topScore: 0,
          runnerUpScore: 0,
          imageQualityScore: 0.5,
        ),
        returnsNormally,
      );
    });
  });

  group('ScannerThresholds', () {
    test('defaults are consistent', () {
      expect(const ScannerThresholds().isConsistent, isTrue);
    });

    test('does not require validation for medium confidence by default', () {
      // Whether medium-confidence answers need human eyes is an empirical
      // question for the calibration dataset, so it is configurable and off.
      expect(
        const ScannerThresholds().requireValidationForMediumConfidence,
        isFalse,
      );
    });

    test('round-trips through JSON', () {
      const ScannerThresholds original = ScannerThresholds(
        version: 4,
        bubbles: BubbleThresholds(blankThreshold: 0.3),
        requireValidationForMediumConfidence: true,
      );
      final ScannerThresholds? parsed = ScannerThresholds.tryFromJson(
        original.toJson(),
      );
      expect(parsed, isNotNull);
      expect(parsed!.version, 4);
      expect(parsed.bubbles.blankThreshold, 0.3);
      expect(parsed.requireValidationForMediumConfidence, isTrue);
    });

    test('rejects an inconsistent configuration instead of applying it', () {
      // The caller keeps the previous set and logs the rejection. Applying an
      // inverted set would silently reclassify every answer.
      final ScannerThresholds? parsed = ScannerThresholds.tryFromJson(
        <String, Object?>{
          'version': 2,
          'bubbles': <String, Object?>{
            'blankThreshold': 0.9,
            'filledThreshold': 0.1,
          },
        },
      );
      expect(parsed, isNull);
    });

    test('falls back to defaults for missing sections', () {
      final ScannerThresholds? parsed = ScannerThresholds.tryFromJson(
        <String, Object?>{'version': 7},
      );
      expect(parsed, isNotNull);
      expect(parsed!.version, 7);
      expect(
        parsed.bubbles.blankThreshold,
        const BubbleThresholds().blankThreshold,
      );
    });

    test('ignores non-numeric values rather than crashing', () {
      final ScannerThresholds? parsed = ScannerThresholds.tryFromJson(
        <String, Object?>{
          'bubbles': <String, Object?>{'blankThreshold': 'quite dark'},
        },
      );
      expect(parsed, isNotNull);
      expect(
        parsed!.bubbles.blankThreshold,
        const BubbleThresholds().blankThreshold,
      );
    });

    test('copyWith preserves everything not named', () {
      const ScannerThresholds original = ScannerThresholds(version: 3);
      final ScannerThresholds updated = original.copyWith(version: 4);
      expect(updated.version, 4);
      expect(updated.bubbles.blankThreshold, original.bubbles.blankThreshold);
    });
  });

  group('ImageQualityThresholds', () {
    test('bounds brightness on both sides', () {
      // Over-exposure is as unreadable as darkness, and a single lower bound
      // would pass a washed-out photograph.
      const ImageQualityThresholds t = ImageQualityThresholds();
      expect(t.minBrightness, lessThan(t.maxBrightness));
      expect(t.maxBrightness, lessThan(1.0));
    });

    test('expresses resolution against physical size, not pixels', () {
      // So the floor holds for any sheet size or camera.
      expect(
        const ImageQualityThresholds().minPixelsPerMillimetre,
        greaterThan(0),
      );
    });

    test('round-trips through JSON', () {
      const ImageQualityThresholds original = ImageQualityThresholds(
        minBlurScore: 0.4,
        maxRotationDegrees: 12,
      );
      final ImageQualityThresholds parsed = ImageQualityThresholds.fromJson(
        original.toJson(),
      );
      expect(parsed.minBlurScore, 0.4);
      expect(parsed.maxRotationDegrees, 12);
    });
  });
}
