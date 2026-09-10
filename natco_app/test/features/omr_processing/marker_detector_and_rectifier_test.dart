/// Tests for [MarkerDetector] and [SheetRectifier] together: detecting the
/// four markers in a synthetic sheet, resolving its notch, and rectifying it
/// so a known bubble position reads back correctly — including the
/// deliberately-inverted case that proves an upside-down sheet is detected
/// rather than silently misread (docs/08-mvp-implementation-plan.md Phase 6
/// exit criteria).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:natco_app/features/omr_processing/domain/entity/marker_corner.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/service/marker_detector.dart';
import 'package:natco_app/features/omr_processing/domain/service/sheet_rectifier.dart';

import '../../../tool/synthetic_omr_sheet.dart';

void main() {
  late OmrTemplate template;

  setUpAll(() {
    final String source = File(
      'assets/omr_templates/natco_v1.json',
    ).readAsStringSync();
    template = OmrTemplate.fromJsonString(source);
  });

  /// Mean luminance of a small disc around [questionNumber]/[optionIndex] in
  /// the rectified image — dark for a filled bubble, light for a blank one.
  double sampleLuminance(
    img.Image rectified, {
    required int questionNumber,
    required int optionIndex,
  }) {
    final centre = template.bubbleCentrePx(
      questionNumber: questionNumber,
      optionIndex: optionIndex,
    );
    final int cx = centre.x.round();
    final int cy = centre.y.round();
    const int r = 4;
    double sum = 0;
    int count = 0;
    for (int y = cy - r; y <= cy + r; y++) {
      for (int x = cx - r; x <= cx + r; x++) {
        sum += rectified.getPixel(x, y).luminanceNormalized;
        count++;
      }
    }
    return sum / count;
  }

  test('detects all four markers in an upright synthetic sheet', () {
    final sheet = renderSyntheticSheet(template);
    final result = const MarkerDetector().detect(sheet.image);
    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull!.markersByQuadrant.keys, hasLength(4));
    expect(result.valueOrNull!.notchQuadrant, MarkerCorner.bottomLeft);
  });

  test('fails cleanly when a corner marker is missing', () {
    final sheet = renderSyntheticSheet(template);
    // Paint over the top-left marker with white, simulating a folded or
    // occluded corner.
    img.fillRect(
      sheet.image,
      x1: 0,
      y1: 0,
      x2: 100,
      y2: 100,
      color: img.ColorRgb8(255, 255, 255),
    );
    final result = const MarkerDetector().detect(sheet.image);
    expect(result.isFailure, isTrue);
  });

  test('rectifying an upright sheet reads filled and blank bubbles correctly', () {
    final sheet = renderSyntheticSheet(
      template,
      filledOptions: <int, List<int>>{
        1: <int>[1], // B
        2: <int>[], // blank
      },
    );
    final detection = const MarkerDetector().detect(sheet.image).valueOrNull!;
    final img.Image rectified = const SheetRectifier().rectify(
      sheet.image,
      detection: detection,
      template: template,
    );

    expect(rectified.width, template.rectifiedWidthPx);
    expect(rectified.height, template.rectifiedHeightPx);

    final double filledLuminance = sampleLuminance(
      rectified,
      questionNumber: 1,
      optionIndex: 1,
    );
    final double blankLuminance = sampleLuminance(
      rectified,
      questionNumber: 1,
      optionIndex: 0,
    );
    expect(filledLuminance, lessThan(0.4));
    expect(blankLuminance, greaterThan(0.6));
  });

  test(
    'a sheet photographed upside down still reads correctly after rectification',
    () {
      final sheet = renderSyntheticSheet(
        template,
        filledOptions: <int, List<int>>{
          1: <int>[2], // C
        },
      );
      final img.Image rotated = img.copyRotate(sheet.image, angle: 180);

      final detection = const MarkerDetector().detect(rotated).valueOrNull!;
      expect(detection.notchQuadrant, isNot(MarkerCorner.bottomLeft));

      final img.Image rectified = const SheetRectifier().rectify(
        rotated,
        detection: detection,
        template: template,
      );
      expect(rectified.width, template.rectifiedWidthPx);
      expect(rectified.height, template.rectifiedHeightPx);

      final double filledLuminance = sampleLuminance(
        rectified,
        questionNumber: 1,
        optionIndex: 2,
      );
      final double blankLuminanceA = sampleLuminance(
        rectified,
        questionNumber: 1,
        optionIndex: 0,
      );
      expect(filledLuminance, lessThan(0.4));
      expect(blankLuminanceA, greaterThan(0.6));
    },
  );
}
