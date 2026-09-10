/// Pure image-quality analysis (docs/07-omr-pipeline.md Steps 1-2).
///
/// Deliberately pure: given the same bytes and the same thresholds, it
/// always returns the same report. No file I/O, no repository, nothing that
/// depends on when or on which device it runs — which is what makes it
/// regression-testable against a fixed set of images with no camera and no
/// emulator (docs/07-omr-pipeline.md §5's stated reason for choosing pure
/// Dart first).
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/omr_capture/domain/entity/image_quality_report.dart';

/// Long edge a frame is downscaled to before analysis — flat memory and
/// runtime across devices regardless of the camera's native resolution
/// (docs/07-omr-pipeline.md Step 1).
const int kOmrWorkingLongEdge = 1600;

/// The grid size the shadow/uneven-lighting check divides the frame into.
const int kShadowGridSize = 4;

/// Curve half-point for turning a raw Laplacian variance into a 0.0-1.0
/// score: `variance == kBlurVarianceHalfPoint` maps to a blur score of 0.5.
/// A starting point for calibration against real photographs, not a
/// validated value (docs/07-omr-pipeline.md, the same posture
/// `ScannerThresholds`'s own defaults take).
const double kBlurVarianceHalfPoint = 0.01;

final class ImageQualityAnalyzer {
  const ImageQualityAnalyzer();

  /// Analyses [jpegBytes] against [thresholds]. Fails only when the bytes
  /// cannot be decoded as an image at all — a bad photo is a `FAIL` verdict,
  /// not a [Failure]; an undecodable file is the actual error case.
  Result<ImageQualityReport> analyse(
    Uint8List jpegBytes, {
    required ImageQualityThresholds thresholds,
  }) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(jpegBytes);
    } catch (_) {
      // A handful of malformed byte sequences make `package:image`'s format
      // sniffers throw instead of returning null (e.g. a short buffer that
      // matches enough of a format's magic bytes to attempt a header read).
      // Either way the file is unreadable, which is this method's ordinary
      // `Failure` case, not a bug to propagate.
      decoded = null;
    }
    if (decoded == null) {
      return err(
        const ValidationFailure(
          userMessage: 'That file could not be read as an image.',
        ),
      );
    }
    final img.Image working = _downscale(decoded, kOmrWorkingLongEdge);
    final List<List<double>> luminance = _luminanceGrid(working);

    final double brightness = _meanOf(luminance);
    final double contrast = _percentileSpread(luminance);
    final double blur = _blurScore(luminance);
    final double shadowDeviation = _maxBlockDeviation(
      luminance,
      overallMean: brightness,
      gridSize: kShadowGridSize,
    );

    final List<String> reasons = <String>[
      if (blur < thresholds.minBlurScore)
        'The photo is blurred. Hold the phone steady and retake.',
      if (brightness < thresholds.minBrightness) 'The photo is too dark.',
      if (brightness > thresholds.maxBrightness) 'The photo is too bright.',
      if (contrast < thresholds.minContrast)
        'The sheet is washed out. Avoid direct glare.',
      if (shadowDeviation > thresholds.maxShadowDeviation)
        'Part of the sheet is in shadow.',
    ];

    return ok(
      ImageQualityReport(
        blurScore: blur,
        brightnessScore: brightness,
        contrastScore: contrast,
        shadowDeviation: shadowDeviation,
        verdict: reasons.isEmpty
            ? ImageQualityVerdict.pass
            : ImageQualityVerdict.fail,
        failureReasons: reasons,
      ),
    );
  }

  img.Image _downscale(img.Image image, int longEdge) {
    final int longestSide = image.width > image.height
        ? image.width
        : image.height;
    if (longestSide <= longEdge) {
      return image;
    }
    return image.width >= image.height
        ? img.copyResize(image, width: longEdge)
        : img.copyResize(image, height: longEdge);
  }

  /// Row-major grid of normalised (0.0-1.0) luminance values. Computed once
  /// and reused by every metric below, so a large frame is walked a fixed
  /// number of times rather than once per metric.
  List<List<double>> _luminanceGrid(img.Image image) => <List<double>>[
    for (int y = 0; y < image.height; y++)
      <double>[
        for (int x = 0; x < image.width; x++)
          image.getPixel(x, y).luminanceNormalized.toDouble(),
      ],
  ];

  double _meanOf(List<List<double>> grid) {
    double sum = 0;
    int count = 0;
    for (final List<double> row in grid) {
      for (final double value in row) {
        sum += value;
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  }

  /// `p95 - p5` of the luminance distribution: a washed-out or flatly-lit
  /// sheet has every pixel clustered near one value and a small spread; a
  /// sheet with real black-on-white contrast spans nearly the whole range.
  double _percentileSpread(List<List<double>> grid) {
    final List<double> sorted = <double>[
      for (final List<double> row in grid) ...row,
    ]..sort();
    if (sorted.isEmpty) {
      return 0;
    }
    double percentile(double p) {
      final int index = (p * (sorted.length - 1)).round().clamp(
        0,
        sorted.length - 1,
      );
      return sorted[index];
    }

    return percentile(0.95) - percentile(0.05);
  }

  /// Variance of a discrete Laplacian response, turned into a 0.0-1.0 score.
  /// A sharp image has strong edges and high variance in the Laplacian
  /// response; a blurred one has weak edges everywhere and low variance.
  double _blurScore(List<List<double>> grid) {
    final int height = grid.length;
    final int width = height == 0 ? 0 : grid[0].length;
    if (height < 3 || width < 3) {
      return 0;
    }
    final List<double> responses = <double>[];
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final double response =
            grid[y - 1][x] +
            grid[y + 1][x] +
            grid[y][x - 1] +
            grid[y][x + 1] -
            4 * grid[y][x];
        responses.add(response);
      }
    }
    final double mean = responses.reduce((double a, double b) => a + b) /
        responses.length;
    final double variance =
        responses
            .map((double r) => (r - mean) * (r - mean))
            .reduce((double a, double b) => a + b) /
        responses.length;
    // A saturating curve rather than a linear scale: variance is unbounded
    // above, but the score this feeds into is not.
    return variance / (variance + kBlurVarianceHalfPoint);
  }

  /// The largest absolute difference between any block's mean luminance and
  /// the frame's overall mean, over a [gridSize] x [gridSize] grid of
  /// blocks — a sheet lit evenly has every block close to the overall mean;
  /// one lit from a single side has one corner markedly brighter or darker
  /// than the rest, which a single global brightness check would miss
  /// entirely.
  double _maxBlockDeviation(
    List<List<double>> grid, {
    required double overallMean,
    required int gridSize,
  }) {
    final int height = grid.length;
    final int width = height == 0 ? 0 : grid[0].length;
    if (height == 0 || width == 0) {
      return 0;
    }
    final int blockHeight = (height / gridSize).ceil().clamp(1, height);
    final int blockWidth = (width / gridSize).ceil().clamp(1, width);
    double maxDeviation = 0;
    for (int blockY = 0; blockY < height; blockY += blockHeight) {
      for (int blockX = 0; blockX < width; blockX += blockWidth) {
        final int endY = (blockY + blockHeight).clamp(0, height);
        final int endX = (blockX + blockWidth).clamp(0, width);
        double sum = 0;
        int count = 0;
        for (int y = blockY; y < endY; y++) {
          for (int x = blockX; x < endX; x++) {
            sum += grid[y][x];
            count++;
          }
        }
        if (count == 0) {
          continue;
        }
        final double blockMean = sum / count;
        final double deviation = (blockMean - overallMean).abs();
        if (deviation > maxDeviation) {
          maxDeviation = deviation;
        }
      }
    }
    return maxDeviation;
  }
}
