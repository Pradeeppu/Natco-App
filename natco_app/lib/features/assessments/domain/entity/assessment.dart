/// An assessment definition (docs/02-data-model.md section 4).
///
/// Deliberately carries no school/cluster/district/state ancestry: the
/// definition itself — its questions, its option set, its answer key — is
/// shared across the whole system, the same paper printed everywhere it is
/// assigned. What *is* scoped to a school is the
/// [AssessmentAssignment], `AssessmentSession` and every OMR/result record
/// beneath it. Filtering assessments themselves by `AccessScope` would only
/// hide a shared definition from someone allowed to see its results.
library;

import 'package:natco_app/features/assessments/domain/entity/assessment_status.dart';
import 'package:natco_app/features/assessments/domain/entity/question_type.dart';

final class Assessment {
  const Assessment({
    required this.assessmentId,
    required this.assessmentName,
    required this.assessmentCode,
    required this.academicYear,
    required this.grade,
    required this.subject,
    required this.questionCount,
    required this.questionType,
    required this.options,
    required this.durationMinutes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.instructions = '',
    this.marksPerQuestion = 1,
    this.negativeMarksPerWrong = 0,
    this.activeAnswerKeyVersion,
  });

  final String assessmentId;
  final String assessmentName;

  /// Unique; printed on the OMR sheet. Fixed once set — sheets already
  /// printed against it cannot be repointed at a different assessment.
  final String assessmentCode;

  final String academicYear;
  final String grade;
  final String subject;
  final int questionCount;
  final QuestionType questionType;

  /// The option letters offered, e.g. `[A, B, C, D]`.
  final List<String> options;

  final int durationMinutes;
  final String instructions;
  final double marksPerQuestion;
  final double negativeMarksPerWrong;

  /// The answer-key version currently in force. `null` until a key is
  /// published for the first time (docs/02-data-model.md section 4).
  final int? activeAnswerKeyVersion;

  final AssessmentStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  Assessment copyWith({
    String? assessmentName,
    int? durationMinutes,
    String? instructions,
    double? marksPerQuestion,
    double? negativeMarksPerWrong,
    int? activeAnswerKeyVersion,
    AssessmentStatus? status,
    DateTime? updatedAt,
  }) => Assessment(
    assessmentId: assessmentId,
    assessmentName: assessmentName ?? this.assessmentName,
    assessmentCode: assessmentCode,
    academicYear: academicYear,
    grade: grade,
    subject: subject,
    questionCount: questionCount,
    questionType: questionType,
    options: options,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    instructions: instructions ?? this.instructions,
    marksPerQuestion: marksPerQuestion ?? this.marksPerQuestion,
    negativeMarksPerWrong: negativeMarksPerWrong ?? this.negativeMarksPerWrong,
    activeAnswerKeyVersion:
        activeAnswerKeyVersion ?? this.activeAnswerKeyVersion,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'assessmentId': assessmentId,
    'assessmentName': assessmentName,
    'assessmentCode': assessmentCode,
    'academicYear': academicYear,
    'grade': grade,
    'subject': subject,
    'questionCount': questionCount,
    'questionType': questionType.wireName,
    'options': options,
    'durationMinutes': durationMinutes,
    'instructions': instructions,
    'marksPerQuestion': marksPerQuestion,
    'negativeMarksPerWrong': negativeMarksPerWrong,
    'activeAnswerKeyVersion': activeAnswerKeyVersion,
    'status': status.wireName,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  /// Reads an assessment from stored JSON. Returns `null` when identity or
  /// an enum field cannot be resolved — the same fail-closed posture as
  /// `School.tryFromJson` and `Student.tryFromJson`.
  static Assessment? tryFromJson(Map<String, Object?> json) {
    final String? assessmentId = json['assessmentId'] as String?;
    final String? assessmentName = json['assessmentName'] as String?;
    final String? assessmentCode = json['assessmentCode'] as String?;
    final String? academicYear = json['academicYear'] as String?;
    final String? grade = json['grade'] as String?;
    final String? subject = json['subject'] as String?;
    final int? questionCount = (json['questionCount'] as num?)?.toInt();
    final QuestionType? questionType = QuestionType.tryFromWireName(
      json['questionType'] as String?,
    );
    final AssessmentStatus? status = AssessmentStatus.tryFromWireName(
      json['status'] as String?,
    );
    final DateTime? createdAt = _parseUtc(json['createdAt']);
    final DateTime? updatedAt = _parseUtc(json['updatedAt']);
    if (assessmentId == null ||
        assessmentName == null ||
        assessmentCode == null ||
        academicYear == null ||
        grade == null ||
        subject == null ||
        questionCount == null ||
        questionType == null ||
        status == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    return Assessment(
      assessmentId: assessmentId,
      assessmentName: assessmentName,
      assessmentCode: assessmentCode,
      academicYear: academicYear,
      grade: grade,
      subject: subject,
      questionCount: questionCount,
      questionType: questionType,
      options: (json['options'] as List<Object?>? ?? const <Object?>[])
          .map((Object? o) => o.toString())
          .toList(growable: false),
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
      instructions: json['instructions'] as String? ?? '',
      marksPerQuestion: (json['marksPerQuestion'] as num?)?.toDouble() ?? 1,
      negativeMarksPerWrong:
          (json['negativeMarksPerWrong'] as num?)?.toDouble() ?? 0,
      activeAnswerKeyVersion: (json['activeAnswerKeyVersion'] as num?)?.toInt(),
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static DateTime? _parseUtc(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}
