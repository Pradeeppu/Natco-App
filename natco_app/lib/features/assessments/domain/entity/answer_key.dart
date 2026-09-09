/// One versioned answer key for an [Assessment] (docs/02-data-model.md
/// section 4, Critical Rules 5-6).
///
/// A [Result] records the `answerKeyVersion` it was scored against, so an
/// old score always stays explainable even after a correction supersedes the
/// key it was scored with — nothing here ever overwrites a prior version's
/// answers.
library;

import 'package:natco_app/features/assessments/domain/entity/answer_key_status.dart';

final class AnswerKey {
  const AnswerKey({
    required this.answerKeyId,
    required this.assessmentId,
    required this.version,
    required this.answers,
    required this.status,
    required this.createdAt,
    this.publishedBy,
    this.publishedAt,
    this.supersededBy,
    this.changeReason,
  });

  final String answerKeyId;
  final String assessmentId;

  /// Monotonic from 1.
  final int version;

  /// Question number to correct option.
  final Map<int, String> answers;

  final AnswerKeyStatus status;
  final String? publishedBy;
  final DateTime? publishedAt;

  /// The id of the version that superseded this one. Set only once this
  /// key's own status has moved to [AnswerKeyStatus.superseded].
  final String? supersededBy;

  /// Mandatory for every version after the first (requirement: a correction
  /// must say why).
  final String? changeReason;

  final DateTime createdAt;

  AnswerKey supersededByVersion(String nextAnswerKeyId) => AnswerKey(
    answerKeyId: answerKeyId,
    assessmentId: assessmentId,
    version: version,
    answers: answers,
    status: AnswerKeyStatus.superseded,
    publishedBy: publishedBy,
    publishedAt: publishedAt,
    supersededBy: nextAnswerKeyId,
    changeReason: changeReason,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'answerKeyId': answerKeyId,
    'assessmentId': assessmentId,
    'version': version,
    // Firestore/JSON map keys are always strings; question numbers are
    // re-parsed back to `int` in `tryFromJson`.
    'answers': answers.map(
      (int questionNumber, String option) =>
          MapEntry<String, Object?>('$questionNumber', option),
    ),
    'status': status.wireName,
    'publishedBy': publishedBy,
    'publishedAt': publishedAt?.toUtc().toIso8601String(),
    'supersededBy': supersededBy,
    'changeReason': changeReason,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static AnswerKey? tryFromJson(Map<String, Object?> json) {
    final String? answerKeyId = json['answerKeyId'] as String?;
    final String? assessmentId = json['assessmentId'] as String?;
    final int? version = (json['version'] as num?)?.toInt();
    final AnswerKeyStatus? status = _statusFromWireName(
      json['status'] as String?,
    );
    final DateTime? createdAt = _parseUtc(json['createdAt']);
    if (answerKeyId == null ||
        assessmentId == null ||
        version == null ||
        status == null ||
        createdAt == null) {
      return null;
    }
    final Object? rawAnswers = json['answers'];
    final Map<int, String> answers = <int, String>{
      if (rawAnswers is Map)
        for (final MapEntry<Object?, Object?> entry in rawAnswers.entries)
          if (int.tryParse(entry.key.toString()) case final int questionNumber)
            questionNumber: entry.value.toString(),
    };
    return AnswerKey(
      answerKeyId: answerKeyId,
      assessmentId: assessmentId,
      version: version,
      answers: answers,
      status: status,
      publishedBy: json['publishedBy'] as String?,
      publishedAt: _parseUtc(json['publishedAt']),
      supersededBy: json['supersededBy'] as String?,
      changeReason: json['changeReason'] as String?,
      createdAt: createdAt,
    );
  }

  static AnswerKeyStatus? _statusFromWireName(String? name) {
    for (final AnswerKeyStatus status in AnswerKeyStatus.values) {
      if (status.wireName == name) {
        return status;
      }
    }
    return null;
  }

  static DateTime? _parseUtc(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}
