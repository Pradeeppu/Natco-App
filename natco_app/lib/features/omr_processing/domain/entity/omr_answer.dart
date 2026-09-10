/// One question's machine (and, later, human) answer for one sheet
/// (docs/02-data-model.md §6, `OmrAnswer`) — one record per question per
/// submission.
///
/// Scoped to what Phase 6 (the detection engine) actually produces.
/// `finalAnswer`, `finalAnswerSource`, `isCorrect`, `marks`, `validatedBy`,
/// `validatedAt`, `validationReason` and `bubbleCropPath` are documented
/// fields of the eventual answer record but are absent here rather than
/// present-and-null: nothing in this phase runs a human validation pass,
/// scores anything, or crops a bubble image for a reviewer to see — the
/// same "omit until meaningful" pattern `OmrSubmission` already follows for
/// its own not-yet-computed fields (docs/08-mvp-implementation-plan.md
/// Phase 5 notes). Phase 7 adds the validation fields once a review queue
/// exists; Phase 8 adds `isCorrect`/`marks` once scoring exists.
library;

import 'package:natco_app/features/omr_processing/domain/entity/detection_status.dart';

final class OmrAnswer {
  const OmrAnswer({
    required this.omrAnswerId,
    required this.omrId,
    required this.questionNumber,
    required this.optionScores,
    required this.machineAnswer,
    required this.machineConfidence,
    required this.machineStatus,
  });

  final String omrAnswerId;

  /// The sheet this answer belongs to — matches `OmrSubmission.omrId`, not
  /// its internal `submissionId`, per the documented schema.
  final String omrId;

  final int questionNumber;

  /// Per-option fill score (0.0-1.0), kept as evidence even for options
  /// that were not chosen — machine fields are written once and never
  /// updated (docs/02-data-model.md §6, Critical Rule 3).
  final Map<String, double> optionScores;

  /// `null` for [DetectionStatus.blank] and [DetectionStatus.multipleMark].
  final String? machineAnswer;
  final double machineConfidence;
  final DetectionStatus machineStatus;

  Map<String, Object?> toJson() => <String, Object?>{
    'omrAnswerId': omrAnswerId,
    'omrId': omrId,
    'questionNumber': questionNumber,
    'optionScores': optionScores,
    'machineAnswer': machineAnswer,
    'machineConfidence': machineConfidence,
    'machineStatus': machineStatus.wireName,
  };

  static OmrAnswer? tryFromJson(Map<String, Object?> json) {
    final String? omrAnswerId = json['omrAnswerId'] as String?;
    final String? omrId = json['omrId'] as String?;
    final Object? questionNumber = json['questionNumber'];
    final Object? rawScores = json['optionScores'];
    final DetectionStatus? machineStatus = DetectionStatus.tryFromWireName(
      json['machineStatus'] as String? ?? '',
    );
    final Object? rawConfidence = json['machineConfidence'];
    if (omrAnswerId == null ||
        omrId == null ||
        questionNumber is! int ||
        rawScores is! Map<String, Object?> ||
        machineStatus == null ||
        rawConfidence is! num) {
      return null;
    }
    return OmrAnswer(
      omrAnswerId: omrAnswerId,
      omrId: omrId,
      questionNumber: questionNumber,
      optionScores: rawScores.map(
        (String key, Object? value) => MapEntry(key, (value as num).toDouble()),
      ),
      machineAnswer: json['machineAnswer'] as String?,
      machineConfidence: rawConfidence.toDouble(),
      machineStatus: machineStatus,
    );
  }
}
