/// Tests for [BubbleSampler] against real rendered (and rectified)
/// synthetic sheets — a filled bubble must score noticeably higher than a
/// blank one, for every option on a question, not just one hand-picked
/// case.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/service/bubble_sampler.dart';
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

  img.Image rectifiedOf(Map<int, List<int>> filledOptions) {
    final sheet = renderSyntheticSheet(template, filledOptions: filledOptions);
    final detection = const MarkerDetector().detect(sheet.image).valueOrNull!;
    return const SheetRectifier().rectify(
      sheet.image,
      detection: detection,
      template: template,
    );
  }

  const BubbleThresholds thresholds = BubbleThresholds();
  const BubbleSampler sampler = BubbleSampler();

  test('a filled option scores clearly higher than the others', () {
    final img.Image rectified = rectifiedOf(<int, List<int>>{
      5: <int>[2], // C
    });
    final scores = sampler.sampleQuestion(
      rectified,
      template: template,
      questionNumber: 5,
      thresholds: thresholds,
    );
    expect(scores.keys.toSet(), <String>{'A', 'B', 'C', 'D'});
    expect(scores['C'], greaterThan(thresholds.filledThreshold));
    for (final String other in <String>['A', 'B', 'D']) {
      expect(scores[other], lessThan(thresholds.blankThreshold));
      expect(scores['C']! - scores[other]!, greaterThan(thresholds.clearMargin));
    }
  });

  test('every option scores low on a fully blank question', () {
    final img.Image rectified = rectifiedOf(const <int, List<int>>{});
    final scores = sampler.sampleQuestion(
      rectified,
      template: template,
      questionNumber: 42,
      thresholds: thresholds,
    );
    for (final double score in scores.values) {
      expect(score, lessThan(thresholds.blankThreshold));
    }
  });

  test('two filled options both score high, for a multiple-mark question', () {
    final img.Image rectified = rectifiedOf(<int, List<int>>{
      10: <int>[0, 1], // A and B
    });
    final scores = sampler.sampleQuestion(
      rectified,
      template: template,
      questionNumber: 10,
      thresholds: thresholds,
    );
    expect(scores['A'], greaterThan(thresholds.multipleMarkThreshold));
    expect(scores['B'], greaterThan(thresholds.multipleMarkThreshold));
    expect(scores['C'], lessThan(thresholds.blankThreshold));
    expect(scores['D'], lessThan(thresholds.blankThreshold));
  });

  test('sampling every question on the template does not throw', () {
    final img.Image rectified = rectifiedOf(<int, List<int>>{1: <int>[0]});
    for (int q = 1; q <= template.questionCount; q++) {
      final scores = sampler.sampleQuestion(
        rectified,
        template: template,
        questionNumber: q,
        thresholds: thresholds,
      );
      expect(scores, hasLength(4));
    }
  });
}
