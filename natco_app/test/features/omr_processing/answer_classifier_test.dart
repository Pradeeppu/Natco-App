/// Tests for [AnswerClassifier] against docs/07-omr-pipeline.md Step 9's
/// classification cascade.
///
/// Three of the doc's four worked examples are used verbatim below (they
/// are internally consistent with the doc's own stated default
/// thresholds); the fourth ("0.72/0.69 -> LOW_CONFIDENCE") is not, since
/// 0.69 already clears the documented default `multipleMarkThreshold`
/// (0.55), which this cascade — implemented exactly as specified —
/// correctly classifies as MULTIPLE_MARK instead. Rather than assert a
/// result the specified thresholds cannot actually produce, medium- and
/// low-confidence cases below are constructed directly against the real
/// default thresholds.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/features/omr_processing/domain/entity/detection_status.dart';
import 'package:natco_app/features/omr_processing/domain/entity/question_detection_result.dart';
import 'package:natco_app/features/omr_processing/domain/service/answer_classifier.dart';

void main() {
  const AnswerClassifier classifier = AnswerClassifier();
  const BubbleThresholds thresholds = BubbleThresholds();
  const ConfidenceWeights confidenceWeights = ConfidenceWeights();
  const List<String> options = <String>['A', 'B', 'C', 'D'];

  QuestionDetectionResult classify(Map<String, double> scores) =>
      classifier.classify(
        questionNumber: 1,
        optionScores: scores,
        optionLabels: options,
        thresholds: thresholds,
        confidenceWeights: confidenceWeights,
        imageQualityScore: 1.0,
      );

  test('a clear single fill is HIGH_CONFIDENCE (doc worked example)', () {
    final result = classify(<String, double>{
      'A': 0.10,
      'B': 0.91,
      'C': 0.12,
      'D': 0.09,
    });
    expect(result.machineStatus, DetectionStatus.highConfidence);
    expect(result.machineAnswer, 'B');
  });

  test('near-uniform faint scores are BLANK (doc worked example)', () {
    final result = classify(<String, double>{
      'A': 0.08,
      'B': 0.09,
      'C': 0.07,
      'D': 0.06,
    });
    expect(result.machineStatus, DetectionStatus.blank);
    expect(result.machineAnswer, isNull);
  });

  test('two strong fills are MULTIPLE_MARK (doc worked example)', () {
    final result = classify(<String, double>{
      'A': 0.84,
      'B': 0.81,
      'C': 0.10,
      'D': 0.08,
    });
    expect(result.machineStatus, DetectionStatus.multipleMark);
    expect(result.machineAnswer, isNull);
  });

  test('a middling margin is MEDIUM_CONFIDENCE', () {
    final result = classify(<String, double>{
      'A': 0.50,
      'B': 0.30,
      'C': 0.05,
      'D': 0.05,
    });
    expect(result.machineStatus, DetectionStatus.mediumConfidence);
    expect(result.machineAnswer, 'A');
    expect(result.machineStatus.requiresValidation, isFalse);
  });

  test('a thin margin below a filled top score is LOW_CONFIDENCE', () {
    final result = classify(<String, double>{
      'A': 0.40,
      'B': 0.35,
      'C': 0.05,
      'D': 0.05,
    });
    expect(result.machineStatus, DetectionStatus.lowConfidence);
    expect(result.machineAnswer, 'A');
    expect(result.machineStatus.requiresValidation, isTrue);
  });

  test('confidence score is higher for a clearer margin', () {
    final clear = classify(<String, double>{
      'A': 0.10,
      'B': 0.91,
      'C': 0.12,
      'D': 0.09,
    });
    final thin = classify(<String, double>{
      'A': 0.40,
      'B': 0.35,
      'C': 0.05,
      'D': 0.05,
    });
    expect(clear.machineConfidence, greaterThan(thin.machineConfidence));
  });

  test('a lower image quality score lowers confidence for the same fill pattern', () {
    final good = classifier.classify(
      questionNumber: 1,
      optionScores: <String, double>{'A': 0.10, 'B': 0.91, 'C': 0.12, 'D': 0.09},
      optionLabels: options,
      thresholds: thresholds,
      confidenceWeights: confidenceWeights,
      imageQualityScore: 1.0,
    );
    final poor = classifier.classify(
      questionNumber: 1,
      optionScores: <String, double>{'A': 0.10, 'B': 0.91, 'C': 0.12, 'D': 0.09},
      optionLabels: options,
      thresholds: thresholds,
      confidenceWeights: confidenceWeights,
      imageQualityScore: 0.2,
    );
    expect(good.machineConfidence, greaterThan(poor.machineConfidence));
  });
}
