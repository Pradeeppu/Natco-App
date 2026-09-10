/// Answer classification and confidence (docs/07-omr-pipeline.md
/// Steps 9-10).
library;

import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/features/omr_processing/domain/entity/detection_status.dart';
import 'package:natco_app/features/omr_processing/domain/entity/question_detection_result.dart';

/// Turns per-option fill scores into a status and, for anything with an
/// answer, a confidence score.
///
/// The status cascade below follows docs/07-omr-pipeline.md Step 9's worked
/// examples literally — each example there attributes its label to the raw
/// margin between the top two scores (`"B, HIGH_CONFIDENCE (margin 0.79)"`),
/// not to a blended score. [ConfidenceWeights.score] (Step 10) is computed
/// and stored alongside as a separate, continuous `machineConfidence` value
/// that also folds in image quality — evidence for calibration and
/// reporting, not a second vote on the categorical status. Its own
/// `mediumConfidenceFloor`/`highConfidenceFloor` are left unused by this
/// classifier for that reason: they exist for a later, presentation-facing
/// bucketing of the continuous score, not for deciding `machineStatus`.
final class AnswerClassifier {
  const AnswerClassifier();

  QuestionDetectionResult classify({
    required int questionNumber,
    required Map<String, double> optionScores,
    required List<String> optionLabels,
    required BubbleThresholds thresholds,
    required ConfidenceWeights confidenceWeights,
    required double imageQualityScore,
  }) {
    final List<MapEntry<String, double>> ranked =
        optionLabels
            .map((String label) => MapEntry(label, optionScores[label] ?? 0.0))
            .toList()
          ..sort(
            (MapEntry<String, double> a, MapEntry<String, double> b) =>
                b.value.compareTo(a.value),
          );

    final double top1 = ranked[0].value;
    final double top2 = ranked.length > 1 ? ranked[1].value : 0.0;
    final String topLabel = ranked[0].key;

    final DetectionStatus status;
    String? answer;
    if (top1 < thresholds.blankThreshold) {
      status = DetectionStatus.blank;
    } else if (top2 >= thresholds.multipleMarkThreshold) {
      status = DetectionStatus.multipleMark;
    } else if ((top1 - top2) >= thresholds.clearMargin &&
        top1 >= thresholds.filledThreshold) {
      status = DetectionStatus.highConfidence;
      answer = topLabel;
    } else if ((top1 - top2) >= thresholds.ambiguousMargin) {
      status = DetectionStatus.mediumConfidence;
      answer = topLabel;
    } else {
      status = DetectionStatus.lowConfidence;
      answer = topLabel;
    }

    final double confidence = confidenceWeights.score(
      topScore: top1,
      runnerUpScore: top2,
      imageQualityScore: imageQualityScore,
    );

    return QuestionDetectionResult(
      questionNumber: questionNumber,
      optionScores: optionScores,
      machineAnswer: answer,
      machineConfidence: confidence,
      machineStatus: status,
    );
  }
}
