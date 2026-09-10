/// End-to-end tests for [OmrProcessingPipeline]: raw JPEG bytes in, per-
/// question classification out, against real synthetic sheets rather than
/// hand-built fixtures for every stage.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/features/omr_processing/domain/entity/detection_status.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/service/omr_processing_pipeline.dart';

import '../../../tool/synthetic_omr_sheet.dart';

void main() {
  late OmrTemplate template;

  setUpAll(() {
    final String source = File(
      'assets/omr_templates/natco_v1.json',
    ).readAsStringSync();
    template = OmrTemplate.fromJsonString(source);
  });

  const OmrProcessingPipeline pipeline = OmrProcessingPipeline();
  const ScannerThresholds thresholds = ScannerThresholds();

  Uint8List jpegOf(Map<int, List<int>> filledOptions) {
    final sheet = renderSyntheticSheet(template, filledOptions: filledOptions);
    return Uint8List.fromList(img.encodeJpg(sheet.image, quality: 92));
  }

  test('a clean sheet with clear single fills is fully classified and ready for scoring', () {
    final Uint8List bytes = jpegOf(<int, List<int>>{
      1: <int>[1], // B
      2: <int>[0], // A
      3: <int>[], // blank
    });

    final result = pipeline.process(
      bytes,
      template: template,
      questionCount: 5,
      thresholds: thresholds,
      imageQualityScore: 0.9,
    );

    expect(result.isSuccess, isTrue);
    final outcome = result.valueOrNull!;
    expect(outcome.questionResults, hasLength(5));
    expect(outcome.questionResults[0].machineAnswer, 'B');
    expect(outcome.questionResults[0].machineStatus, DetectionStatus.highConfidence);
    expect(outcome.questionResults[1].machineAnswer, 'A');
    expect(outcome.questionResults[2].machineStatus, DetectionStatus.blank);
    expect(outcome.needsValidation, isFalse);
  });

  test('a multiple-mark question routes the whole sheet to validation', () {
    final Uint8List bytes = jpegOf(<int, List<int>>{
      1: <int>[0, 2], // A and C both filled
    });

    final result = pipeline.process(
      bytes,
      template: template,
      questionCount: 1,
      thresholds: thresholds,
      imageQualityScore: 0.9,
    );

    expect(result.isSuccess, isTrue);
    final outcome = result.valueOrNull!;
    expect(outcome.questionResults.single.machineStatus, DetectionStatus.multipleMark);
    expect(outcome.needsValidation, isTrue);
  });

  test('an overridden quality gate forces validation even with clean answers', () {
    final Uint8List bytes = jpegOf(<int, List<int>>{1: <int>[1]});

    final result = pipeline.process(
      bytes,
      template: template,
      questionCount: 1,
      thresholds: thresholds,
      imageQualityScore: 0.9,
      qualityWasOverridden: true,
    );

    expect(result.valueOrNull!.needsValidation, isTrue);
  });

  test('an undecodable file fails cleanly rather than throwing', () {
    final result = pipeline.process(
      Uint8List.fromList(<int>[1, 2, 3]),
      template: template,
      questionCount: 1,
      thresholds: thresholds,
      imageQualityScore: 0.9,
    );
    expect(result.isFailure, isTrue);
  });

  test('a sheet with no visible markers fails processing rather than guessing', () {
    final img.Image blank = img.Image(width: 600, height: 800);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    final Uint8List bytes = Uint8List.fromList(img.encodeJpg(blank));

    final result = pipeline.process(
      bytes,
      template: template,
      questionCount: 1,
      thresholds: thresholds,
      imageQualityScore: 0.9,
    );
    expect(result.isFailure, isTrue);
  });
}
