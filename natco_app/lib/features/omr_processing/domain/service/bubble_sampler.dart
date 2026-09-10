/// Bubble sampling (docs/07-omr-pipeline.md Step 8).
library;

import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/entity/point2d.dart';

/// Ratio of the sampling disc's radius to the local-background annulus's
/// inner and outer radii — the annulus sits just outside the disc, wide
/// enough to give a stable median without reaching into a neighbouring
/// bubble at the template's own bubble pitch.
const double kAnnulusInnerRatio = 1.15;
const double kAnnulusOuterRatio = 1.7;

/// Samples one bubble position and returns its fill score, per
/// docs/07-omr-pipeline.md Step 8: `meanInk` catches a faint but complete
/// pencil fill, `coverage` catches a dark but partial tick, and the two are
/// combined by [BubbleThresholds]'s configured weights because they fail
/// differently.
final class BubbleSampler {
  const BubbleSampler();

  /// Per-option fill score for every option of [questionNumber], keyed by
  /// the template's own option labels (`OmrAnswer.optionScores`,
  /// docs/02-data-model.md).
  Map<String, double> sampleQuestion(
    img.Image rectified, {
    required OmrTemplate template,
    required int questionNumber,
    required BubbleThresholds thresholds,
  }) {
    final double discRadius =
        template.bubbleRadiusPx() * thresholds.samplingDiameterRatio;
    return <String, double>{
      for (int i = 0; i < template.optionLabels.length; i++)
        template.optionLabels[i]: _fillScore(
          rectified,
          centre: template.bubbleCentrePx(
            questionNumber: questionNumber,
            optionIndex: i,
          ),
          discRadius: discRadius,
          thresholds: thresholds,
        ),
    };
  }

  double _fillScore(
    img.Image image, {
    required Point2D centre,
    required double discRadius,
    required BubbleThresholds thresholds,
  }) {
    final double annulusInner = discRadius * kAnnulusInnerRatio;
    final double annulusOuter = discRadius * kAnnulusOuterRatio;
    final int searchRadius = annulusOuter.ceil();
    final int cx = centre.x.round();
    final int cy = centre.y.round();

    final List<double> discLuminance = <double>[];
    final List<double> annulusLuminance = <double>[];
    for (int y = cy - searchRadius; y <= cy + searchRadius; y++) {
      if (y < 0 || y >= image.height) {
        continue;
      }
      for (int x = cx - searchRadius; x <= cx + searchRadius; x++) {
        if (x < 0 || x >= image.width) {
          continue;
        }
        final double dx = x - centre.x;
        final double dy = y - centre.y;
        final double distance = math.sqrt(dx * dx + dy * dy);
        final double luminance = image.getPixel(x, y).luminanceNormalized
            .toDouble();
        if (distance <= discRadius) {
          discLuminance.add(luminance);
        } else if (distance >= annulusInner && distance <= annulusOuter) {
          annulusLuminance.add(luminance);
        }
      }
    }
    if (discLuminance.isEmpty) {
      return 0;
    }
    final double localBackground = _median(
      annulusLuminance.isEmpty ? <double>[1.0] : annulusLuminance,
    );
    final double discMean =
        discLuminance.reduce((double a, double b) => a + b) /
        discLuminance.length;
    final double meanInk = localBackground <= 0
        ? 0
        : (1 - discMean / localBackground).clamp(0.0, 1.0);

    // A disc pixel counts toward coverage when it sits meaningfully darker
    // than this bubble's own local background, not a global constant — the
    // same local-normalisation reasoning `ImageQualityAnalyzer` uses for
    // shadow detection, applied per bubble instead of per frame quadrant.
    const double coverageMargin = 0.15;
    final double localThreshold = localBackground - coverageMargin;
    final int belowThreshold = discLuminance
        .where((double l) => l < localThreshold)
        .length;
    final double coverage = belowThreshold / discLuminance.length;

    return (thresholds.meanInkWeight * meanInk +
            thresholds.coverageWeight * coverage)
        .clamp(0.0, 1.0);
  }

  double _median(List<double> values) {
    final List<double> sorted = List<double>.from(values)..sort();
    final int mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[mid];
    }
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
