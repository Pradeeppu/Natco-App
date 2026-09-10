/// One question's machine reading — the fields `OmrAnswer`
/// (docs/02-data-model.md) draws its own machine-written fields from.
library;

import 'package:natco_app/features/omr_processing/domain/entity/detection_status.dart';

final class QuestionDetectionResult {
  const QuestionDetectionResult({
    required this.questionNumber,
    required this.optionScores,
    required this.machineAnswer,
    required this.machineConfidence,
    required this.machineStatus,
  });

  final int questionNumber;

  /// Per-option fill score (0.0-1.0), kept as evidence even for the option
  /// that was not chosen.
  final Map<String, double> optionScores;

  /// `null` for [DetectionStatus.blank] and [DetectionStatus.multipleMark] —
  /// there is no single answer to report for either.
  final String? machineAnswer;
  final double machineConfidence;
  final DetectionStatus machineStatus;
}
