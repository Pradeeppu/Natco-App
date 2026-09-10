/// Golden tests: pin `OmrProcessingPipeline`'s output on a small committed
/// set of synthetic sheets, so an algorithm change that alters any label
/// fails here rather than landing quietly
/// (docs/10-omr-calibration-testing.md §4: "Golden tests pin the pipeline's
/// output on a small committed subset").
///
/// A genuine change to the algorithm is expected to need these expectations
/// updated — that update is exactly the point: it forces a conscious look
/// at what changed, backed by a fresh `tool/omr_eval.dart` run, rather than
/// a silent accuracy regression.
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
    template = OmrTemplate.fromJsonString(
      File('assets/omr_templates/natco_v1.json').readAsStringSync(),
    );
  });

  const OmrProcessingPipeline pipeline = OmrProcessingPipeline();
  const ScannerThresholds thresholds = ScannerThresholds();

  const Map<int, List<int>> pattern = <int, List<int>>{
    1: <int>[0],
    2: <int>[1],
    3: <int>[2],
    4: <int>[3],
    5: <int>[],
    6: <int>[0, 2],
  };
  const Map<int, String?> expectedAnswers = <int, String?>{
    1: 'A',
    2: 'B',
    3: 'C',
    4: 'D',
    5: null,
    6: null,
  };
  const Map<int, DetectionStatus> expectedStatuses = <int, DetectionStatus>{
    1: DetectionStatus.highConfidence,
    2: DetectionStatus.highConfidence,
    3: DetectionStatus.highConfidence,
    4: DetectionStatus.highConfidence,
    5: DetectionStatus.blank,
    6: DetectionStatus.multipleMark,
  };

  Uint8List renderJpeg(img.Image Function(img.Image) transform) {
    final sheet = renderSyntheticSheet(template, filledOptions: pattern);
    return Uint8List.fromList(img.encodeJpg(transform(sheet.image), quality: 92));
  }

  test('golden: an upright clean sheet', () {
    final Uint8List bytes = renderJpeg((img.Image i) => i);
    final result = pipeline.process(
      bytes,
      template: template,
      questionCount: 6,
      thresholds: thresholds,
      imageQualityScore: 0.9,
    );
    expect(result.isSuccess, isTrue);
    final outcome = result.valueOrNull!;
    for (final entry in expectedAnswers.entries) {
      final q = outcome.questionResults[entry.key - 1];
      expect(q.machineAnswer, entry.value, reason: 'question ${entry.key}');
      expect(
        q.machineStatus,
        expectedStatuses[entry.key],
        reason: 'question ${entry.key}',
      );
    }
    expect(outcome.needsValidation, isTrue); // question 6 is MULTIPLE_MARK
  });

  test('golden: the same sheet rotated 180 degrees reads identically', () {
    final Uint8List bytes = renderJpeg((img.Image i) => img.copyRotate(i, angle: 180));
    final result = pipeline.process(
      bytes,
      template: template,
      questionCount: 6,
      thresholds: thresholds,
      imageQualityScore: 0.9,
    );
    expect(result.isSuccess, isTrue);
    final outcome = result.valueOrNull!;
    for (final entry in expectedAnswers.entries) {
      final q = outcome.questionResults[entry.key - 1];
      expect(q.machineAnswer, entry.value, reason: 'question ${entry.key}');
      expect(
        q.machineStatus,
        expectedStatuses[entry.key],
        reason: 'question ${entry.key}',
      );
    }
  });

  test('golden: the same sheet rotated 90 degrees reads identically', () {
    final Uint8List bytes = renderJpeg((img.Image i) => img.copyRotate(i, angle: 90));
    final result = pipeline.process(
      bytes,
      template: template,
      questionCount: 6,
      thresholds: thresholds,
      imageQualityScore: 0.9,
    );
    expect(result.isSuccess, isTrue);
    final outcome = result.valueOrNull!;
    for (final entry in expectedAnswers.entries) {
      final q = outcome.questionResults[entry.key - 1];
      expect(q.machineAnswer, entry.value, reason: 'question ${entry.key}');
    }
  });
}
