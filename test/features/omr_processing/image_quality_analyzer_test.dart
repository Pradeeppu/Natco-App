/// Tests for [ImageQualityAnalyzer] against synthetic bitmaps built in the
/// test itself — no camera, no device, no real photo required. Each test
/// constructs an image with a known, deliberate property (flat and gray,
/// a sharp checkerboard, uniformly dark, one shadowed corner) and checks the
/// analyzer's real, computed metrics respond the way that property demands.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/features/omr_processing/domain/entity/image_quality_report.dart';
import 'package:natco_app/features/omr_processing/domain/service/image_quality_analyzer.dart';

Uint8List _solidGray(int value, {int width = 200, int height = 200}) {
  final img.Image image = img.Image(width: width, height: height);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return img.encodePng(image);
}

/// A fine black/white checkerboard — every pixel is a sharp edge against its
/// neighbour, the opposite of a blurred photo, and spans the full
/// brightness range, the opposite of a low-contrast one.
Uint8List _checkerboard({int width = 200, int height = 200, int cell = 2}) {
  final img.Image image = img.Image(width: width, height: height);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final bool isLight = ((x ~/ cell) + (y ~/ cell)).isEven;
      final int value = isLight ? 255 : 0;
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return img.encodePng(image);
}

/// A mid-gray checkerboard with one quadrant driven dark — the "sheet lit
/// from one side" case a single global brightness figure would pass, but a
/// block-wise check must not.
Uint8List _shadowedCorner({int width = 200, int height = 200, int cell = 2}) {
  final img.Image image = img.Image(width: width, height: height);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final bool isLight = ((x ~/ cell) + (y ~/ cell)).isEven;
      final int base = isLight ? 220 : 150;
      final bool inShadowedCorner = x < width ~/ 2 && y < height ~/ 2;
      final int value = inShadowedCorner ? (base * 0.15).round() : base;
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return img.encodePng(image);
}

void main() {
  group('ImageQualityAnalyzer', () {
    test('rejects bytes that are not a decodable image', () {
      final result = ImageQualityAnalyzer.analyze(
        imageBytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
      );
      expect(result.isFailure, isTrue);
    });

    test(
      'a flat, low-contrast, blurred-equivalent image fails with both '
      'reasons named',
      () {
        // Uniform mid-gray: zero edges anywhere (fails blur) and zero
        // spread between its brightest and darkest pixel (fails contrast).
        final result = ImageQualityAnalyzer.analyze(
          imageBytes: _solidGray(128),
        );
        final ImageQualityReport report = result.valueOrNull!;
        expect(report.verdict, QualityVerdict.fail);
        expect(report.canProcess, isFalse);
        expect(
          report.failureReasons.any((String r) => r.contains('blurry')),
          isTrue,
        );
        expect(
          report.failureReasons.any((String r) => r.contains('contrast')),
          isTrue,
        );
      },
    );

    test('a sharp, high-contrast checkerboard passes', () {
      final result = ImageQualityAnalyzer.analyze(
        imageBytes: _checkerboard(),
      );
      final ImageQualityReport report = result.valueOrNull!;
      expect(report.verdict, QualityVerdict.pass);
      expect(report.canProcess, isTrue);
      expect(report.failureReasons, isEmpty);
      expect(report.blurScore, greaterThan(const ImageQualityThresholds().minBlurScore));
      expect(
        report.contrastScore,
        greaterThan(const ImageQualityThresholds().minContrast),
      );
    });

    test('a uniformly dark image fails as too dark, not too blurry', () {
      final result = ImageQualityAnalyzer.analyze(imageBytes: _solidGray(10));
      final ImageQualityReport report = result.valueOrNull!;
      expect(report.verdict, QualityVerdict.fail);
      expect(
        report.failureReasons.any((String r) => r.contains('too dark')),
        isTrue,
      );
    });

    test('a uniformly bright image fails as overexposed', () {
      final result = ImageQualityAnalyzer.analyze(imageBytes: _solidGray(250));
      final ImageQualityReport report = result.valueOrNull!;
      expect(report.verdict, QualityVerdict.fail);
      expect(
        report.failureReasons.any((String r) => r.contains('overexposed')),
        isTrue,
      );
    });

    test(
      'a sheet lit from one side fails on shadow deviation even though it '
      'is sharp and has global contrast',
      () {
        final result = ImageQualityAnalyzer.analyze(
          imageBytes: _shadowedCorner(),
        );
        final ImageQualityReport report = result.valueOrNull!;
        expect(report.verdict, QualityVerdict.fail);
        expect(
          report.failureReasons.any((String r) => r.contains('shadow')),
          isTrue,
        );
      },
    );

    test(
      'reports the original resolution, not the downsampled working size',
      () {
        final result = ImageQualityAnalyzer.analyze(
          imageBytes: _checkerboard(width: 1200, height: 900),
        );
        expect(result.valueOrNull!.resolutionPx, 1200 * 900);
      },
    );

    test(
      'does not attempt sheet or marker detection — that stays phase 6\'s job',
      () {
        final result = ImageQualityAnalyzer.analyze(
          imageBytes: _checkerboard(),
        );
        final ImageQualityReport report = result.valueOrNull!;
        expect(report.sheetDetected, isFalse);
        expect(report.markersDetected, 0);
      },
    );
  });
}
