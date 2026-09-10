/// The image-quality gate: does a raw photo pass before anything OMR-specific
/// even looks at it (docs/08-mvp-implementation-plan.md, phase 5 exit
/// criteria — "each quality failure has its own message").
///
/// Deliberately does **not** attempt sheet or marker detection.
/// `ImageQualityReport.sheetDetected`/`markersDetected`/`rotationDegrees`/
/// `perspectiveSkew` stay at their conservative defaults here — finding the
/// sheet's corners is genuinely phase 6's job (`docs/07-omr-pipeline.md`'s
/// marker/homography stages), and the quality gate has to run *before* that
/// pipeline even starts, on a photo nothing has confirmed is a legible sheet
/// yet. Gating on blur/brightness/contrast/shadow first is what lets a
/// person retake a bad photo before spending any detection work on it.
///
/// Pure Dart, using `package:image` — no camera, no platform channel,
/// testable against a synthetic bitmap with no device.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart';
import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/omr_processing/domain/entity/image_quality_report.dart';

abstract final class ImageQualityAnalyzer {
  /// Photos this large are downsampled before analysis: none of these
  /// metrics need full resolution, and analysing megapixels of image data on
  /// every capture is wasted work on the low-end devices requirement §7
  /// targets. [ImageQualityReport.resolutionPx] still reports the *original*
  /// size — the resolution check that matters is against the whole photo.
  static const int _workingWidth = 640;

  /// Scales the raw variance-of-Laplacian into roughly the 0.0-1.0 range
  /// `ImageQualityThresholds.minBlurScore` is authored in. A starting point,
  /// not a validated value — like every other default in
  /// `scanner_thresholds.dart`, it wants recalibrating against a real
  /// dataset (docs/10-omr-calibration-testing.md), not trusting on faith.
  static const double _blurNormalisation = 40.0;

  static Result<ImageQualityReport> analyze({
    required Uint8List imageBytes,
    ImageQualityThresholds thresholds = const ImageQualityThresholds(),
  }) {
    final Result<Image> decodeResult = guard(
      () {
        final Image? decoded = decodeImage(imageBytes);
        if (decoded == null) {
          throw const FormatException('unrecognised image format');
        }
        return decoded;
      },
      onError: (Object error, StackTrace stackTrace) => ValidationFailure(
        userMessage:
            'That does not look like a photo. Capture the sheet again.',
        diagnostic: 'decodeImage failed: $error',
      ),
    );
    if (decodeResult.isFailure) {
      return err(decodeResult.failureOrNull!);
    }
    final Image original = decodeResult.valueOrNull!;
    final int originalWidth = original.width;
    final int originalHeight = original.height;

    final Image working = originalWidth > _workingWidth
        ? copyResize(original, width: _workingWidth, maintainAspect: true)
        : original;

    final List<double> luminances = working
        .map((Pixel p) => p.luminanceNormalized.toDouble())
        .toList(growable: false);
    final double brightness = _mean(luminances);
    final double contrast = _percentileSpread(luminances, 5, 95);
    final double shadowDeviation = _maxBlockDeviation(working);
    final double blurScore = _blurScore(working);

    final List<String> reasons = <String>[];
    if (blurScore < thresholds.minBlurScore) {
      reasons.add(
        'The photo is too blurry to read reliably. Hold the camera steady, '
        'let it focus, and capture again.',
      );
    }
    if (brightness < thresholds.minBrightness) {
      reasons.add(
        'The photo is too dark to read. Move to better light and capture '
        'again.',
      );
    } else if (brightness > thresholds.maxBrightness) {
      reasons.add(
        'The photo is overexposed. Reduce glare or direct light and capture '
        'again.',
      );
    }
    if (contrast < thresholds.minContrast) {
      reasons.add(
        'There is too little contrast between the paper and the pencil '
        'marks to read them reliably.',
      );
    }
    if (shadowDeviation > thresholds.maxShadowDeviation) {
      reasons.add(
        'Part of the sheet is in shadow. Even out the lighting across the '
        'whole sheet and capture again.',
      );
    }

    final QualityVerdict verdict = reasons.isEmpty
        ? QualityVerdict.pass
        : QualityVerdict.fail;

    return ok(
      ImageQualityReport(
        blurScore: blurScore,
        brightnessScore: brightness,
        contrastScore: contrast,
        resolutionPx: originalWidth * originalHeight,
        // Phase 6's job — see the file doc.
        sheetDetected: false,
        markersDetected: 0,
        rotationDegrees: 0,
        perspectiveSkew: 0,
        verdict: verdict,
        failureReasons: reasons,
      ),
    );
  }

  static double _mean(List<double> values) => values.isEmpty
      ? 0
      : values.reduce((double a, double b) => a + b) / values.length;

  /// The gap between the [highPercentile]th and [lowPercentile]th luminance
  /// values — `ImageQualityThresholds.minContrast`'s own doc comment defines
  /// contrast this way (a "5th-95th percentile luminance spread floor")
  /// rather than as a standard deviation, because a handful of pure-black or
  /// pure-white outlier pixels (a torn corner, a glare spot) should not by
  /// themselves make a genuinely low-contrast sheet look fine.
  static double _percentileSpread(
    List<double> values,
    int lowPercentile,
    int highPercentile,
  ) {
    if (values.isEmpty) {
      return 0;
    }
    final List<double> sorted = List<double>.of(values)..sort();
    double at(int percentile) {
      final int index = ((sorted.length - 1) * percentile / 100)
          .round()
          .clamp(0, sorted.length - 1);
      return sorted[index];
    }

    return at(highPercentile) - at(lowPercentile);
  }

  /// The largest deviation of any 4x4 grid block's mean luminance from the
  /// image's overall mean — catches a sheet lit from one side, which a
  /// single global brightness figure passes cleanly
  /// (`ImageQualityThresholds.maxShadowDeviation`'s own doc comment).
  static double _maxBlockDeviation(Image image) {
    const int grid = 4;
    final int blockWidth = (image.width / grid).ceil();
    final int blockHeight = (image.height / grid).ceil();
    if (blockWidth == 0 || blockHeight == 0) {
      return 0;
    }

    final List<double> blockMeans = <double>[];
    for (int blockY = 0; blockY < grid; blockY++) {
      for (int blockX = 0; blockX < grid; blockX++) {
        double sum = 0;
        int count = 0;
        final int yStart = blockY * blockHeight;
        final int yEnd = math.min(yStart + blockHeight, image.height);
        final int xStart = blockX * blockWidth;
        final int xEnd = math.min(xStart + blockWidth, image.width);
        for (int y = yStart; y < yEnd; y++) {
          for (int x = xStart; x < xEnd; x++) {
            sum += image.getPixel(x, y).luminanceNormalized.toDouble();
            count++;
          }
        }
        if (count > 0) {
          blockMeans.add(sum / count);
        }
      }
    }
    if (blockMeans.isEmpty) {
      return 0;
    }
    final double overallMean = _mean(blockMeans);
    return blockMeans
        .map((double m) => (m - overallMean).abs())
        .reduce((double a, double b) => a > b ? a : b);
  }

  /// Variance of a Laplacian response — the standard "how sharp is this
  /// image" measure `ImageQualityThresholds.minBlurScore`'s own doc comment
  /// names it as. A blurred photo has few sharp edges, so the Laplacian
  /// (which responds to rapid intensity change) stays close to zero
  /// everywhere and its variance is low; a sharp photo has strong edges in
  /// some places and near-zero response in flat regions, giving high
  /// variance.
  static double _blurScore(Image image) {
    final Image laplacian = convolution(
      image,
      filter: const <num>[0, 1, 0, 1, -4, 1, 0, 1, 0],
    );
    final List<double> responses = laplacian
        .map((Pixel p) => p.luminanceNormalized.toDouble())
        .toList(growable: false);
    if (responses.isEmpty) {
      return 0;
    }
    final double mean = _mean(responses);
    final double variance =
        responses
            .map((double r) => (r - mean) * (r - mean))
            .reduce((double a, double b) => a + b) /
        responses.length;
    return (variance * _blurNormalisation).clamp(0.0, 1.0);
  }
}
