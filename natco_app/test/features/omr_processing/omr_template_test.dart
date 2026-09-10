/// Tests for [OmrTemplate]: loading the real shipped asset and the pixel
/// geometry it derives from it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/omr_processing/domain/entity/marker_corner.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/entity/point2d.dart';

void main() {
  late OmrTemplate template;

  setUpAll(() {
    final String source = File(
      'assets/omr_templates/natco_v1.json',
    ).readAsStringSync();
    template = OmrTemplate.fromJsonString(source);
  });

  test('loads the real shipped v1 template', () {
    expect(template.templateVersion, 1);
    expect(template.notchCorner, MarkerCorner.bottomLeft);
    expect(template.optionLabels, <String>['A', 'B', 'C', 'D']);
    expect(template.questionCount, 100);
  });

  test('bubble centres land strictly inside the rectified image bounds', () {
    for (int q = 1; q <= template.questionCount; q++) {
      for (int option = 0; option < template.optionLabels.length; option++) {
        final centre = template.bubbleCentrePx(
          questionNumber: q,
          optionIndex: option,
        );
        expect(
          centre.x,
          inInclusiveRange(0, template.rectifiedWidthPx.toDouble()),
          reason: 'question $q option $option x',
        );
        expect(
          centre.y,
          inInclusiveRange(0, template.rectifiedHeightPx.toDouble()),
          reason: 'question $q option $option y',
        );
      }
    }
  });

  test('option bubbles within a question are evenly spaced', () {
    final Point2D a = template.bubbleCentrePx(questionNumber: 1, optionIndex: 0);
    final Point2D b = template.bubbleCentrePx(questionNumber: 1, optionIndex: 1);
    final Point2D c = template.bubbleCentrePx(questionNumber: 1, optionIndex: 2);
    expect(b.x - a.x, closeTo(c.x - b.x, 0.001));
    expect(a.y, b.y);
    expect(b.y, c.y);
  });

  test('consecutive rows within a column are evenly spaced vertically', () {
    final Point2D row0 = template.bubbleCentrePx(questionNumber: 1, optionIndex: 0);
    final Point2D row1 = template.bubbleCentrePx(questionNumber: 2, optionIndex: 0);
    final Point2D row2 = template.bubbleCentrePx(questionNumber: 3, optionIndex: 0);
    expect(row1.y - row0.y, closeTo(row2.y - row1.y, 0.001));
    expect(row0.x, row1.x);
  });

  test('columnFor throws for a question number outside the grid', () {
    expect(() => template.columnFor(0), throwsArgumentError);
    expect(() => template.columnFor(101), throwsArgumentError);
  });

  test('bubbleRadiusPx is positive and small relative to the rectified width', () {
    final double radius = template.bubbleRadiusPx();
    expect(radius, greaterThan(0));
    expect(radius, lessThan(template.rectifiedWidthPx / 10));
  });
}
