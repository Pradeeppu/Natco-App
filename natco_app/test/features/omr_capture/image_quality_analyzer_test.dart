/// Tests for the pure image-quality analyzer, against synthetic images
/// generated in-memory — no camera, no fixture files, no emulator
/// (docs/07-omr-pipeline.md §5).
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/features/omr_capture/domain/entity/image_quality_report.dart';
import 'package:natco_app/features/omr_capture/domain/service/image_quality_analyzer.dart';

Uint8List _solidColorJpeg(int gray, {int size = 64}) {
  final img.Image image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(gray, gray, gray));
  return Uint8List.fromList(img.encodeJpg(image));
}

Uint8List _checkerboardJpeg({int size = 64, int cell = 4}) {
  final img.Image image = img.Image(width: size, height: size);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final bool isLight = ((x ~/ cell) + (y ~/ cell)).isEven;
      final int gray = isLight ? 245 : 10;
      image.setPixel(x, y, img.ColorRgb8(gray, gray, gray));
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

/// A sheet lit from one side: left half bright, right half dark, each
/// otherwise flat — evenly lit within each half, so this isolates the
/// shadow/uneven-lighting metric from blur or overall brightness.
Uint8List _sideLitJpeg({int size = 64}) {
  final img.Image image = img.Image(width: size, height: size);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final int gray = x < size ~/ 2 ? 235 : 60;
      image.setPixel(x, y, img.ColorRgb8(gray, gray, gray));
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  const ImageQualityAnalyzer analyzer = ImageQualityAnalyzer();
  const ImageQualityThresholds thresholds = ImageQualityThresholds();

  test('fails to decode bytes that are not an image', () {
    final result = analyzer.analyse(
      Uint8List.fromList(<int>[1, 2, 3, 4]),
      thresholds: thresholds,
    );
    expect(result.isFailure, isTrue);
  });

  test('a sharp, high-contrast image scores higher on blur than a flat one', () {
    final sharp = analyzer
        .analyse(_checkerboardJpeg(), thresholds: thresholds)
        .valueOrNull!;
    final flat = analyzer
        .analyse(_solidColorJpeg(128), thresholds: thresholds)
        .valueOrNull!;
    expect(sharp.blurScore, greaterThan(flat.blurScore));
  });

  test('a mid-grey flat image passes brightness and fails blur and contrast', () {
    final report = analyzer
        .analyse(_solidColorJpeg(140), thresholds: thresholds)
        .valueOrNull!;
    expect(report.brightnessScore, closeTo(140 / 255, 0.05));
    expect(report.contrastScore, closeTo(0, 0.01));
    expect(report.verdict, ImageQualityVerdict.fail);
    expect(
      report.failureReasons,
      contains('The photo is blurred. Hold the phone steady and retake.'),
    );
  });

  test('a very dark image fails with "too dark"', () {
    final report = analyzer
        .analyse(_solidColorJpeg(5), thresholds: thresholds)
        .valueOrNull!;
    expect(report.verdict, ImageQualityVerdict.fail);
    expect(report.failureReasons, contains('The photo is too dark.'));
  });

  test('a very bright image fails with "too bright"', () {
    final report = analyzer
        .analyse(_solidColorJpeg(250), thresholds: thresholds)
        .valueOrNull!;
    expect(report.verdict, ImageQualityVerdict.fail);
    expect(report.failureReasons, contains('The photo is too bright.'));
  });

  test('a sharp checkerboard passes blur and contrast', () {
    final report = analyzer
        .analyse(_checkerboardJpeg(), thresholds: thresholds)
        .valueOrNull!;
    expect(report.blurScore, greaterThanOrEqualTo(thresholds.minBlurScore));
    expect(report.contrastScore, greaterThanOrEqualTo(thresholds.minContrast));
  });

  test('a side-lit sheet has a larger shadow deviation than an evenly-lit one', () {
    final sideLit = analyzer
        .analyse(_sideLitJpeg(), thresholds: thresholds)
        .valueOrNull!;
    final even = analyzer
        .analyse(_solidColorJpeg(150), thresholds: thresholds)
        .valueOrNull!;
    expect(sideLit.shadowDeviation, greaterThan(even.shadowDeviation));
  });

  test('every failure gets its own message, not one bundled reason', () {
    // Dark, flat and blurred all at once: three independent failures.
    final report = analyzer
        .analyse(_solidColorJpeg(5), thresholds: thresholds)
        .valueOrNull!;
    expect(report.failureReasons, hasLength(3));
    expect(
      report.failureReasons,
      containsAll(<String>[
        'The photo is blurred. Hold the phone steady and retake.',
        'The photo is too dark.',
        'The sheet is washed out. Avoid direct glare.',
      ]),
    );
  });

  test('report round-trips through JSON', () {
    final report = analyzer
        .analyse(_checkerboardJpeg(), thresholds: thresholds)
        .valueOrNull!;
    final ImageQualityReport? restored = ImageQualityReport.tryFromJson(
      report.toJson(),
    );
    expect(restored?.verdict, report.verdict);
    expect(restored?.blurScore, report.blurScore);
    expect(restored?.failureReasons, report.failureReasons);
  });
}
