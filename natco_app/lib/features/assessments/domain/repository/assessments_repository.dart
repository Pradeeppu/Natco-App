/// Assessment definitions, questions, versioned answer keys and school
/// assignments, as seen by the presentation layer (docs/02-data-model.md
/// section 4).
library;

import 'package:natco_app/core/utils/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_question.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_status.dart';
import 'package:natco_app/features/assessments/domain/entity/assignment_status.dart';
import 'package:natco_app/features/assessments/domain/entity/question_type.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

abstract interface class AssessmentsRepository {
  /// Not scope-restricted: see `Assessment`'s doc comment for why the
  /// definition itself is visible to anyone holding `viewAssessments`, while
  /// [listAssignments] below is where scope actually applies.
  Future<Result<Page<Assessment>>> listAssessments({
    String? query,
    AssessmentStatus? status,
    PageRequest request = PageRequest.first,
  });

  Future<Result<Assessment?>> getAssessment(String assessmentId);

  /// Creates a DRAFT assessment together with [questionCount] blank
  /// questions numbered 1..[questionCount]. Fails with a [DuplicateFailure]
  /// when [assessmentCode] is already in use.
  Future<Result<Assessment>> createAssessment({
    required String assessmentName,
    required String assessmentCode,
    required String academicYear,
    required String grade,
    required String subject,
    required int questionCount,
    required QuestionType questionType,
    required List<String> options,
    required int durationMinutes,
    String instructions,
    double marksPerQuestion,
    double negativeMarksPerWrong,
  });

  Future<Result<Assessment>> updateAssessment(Assessment assessment);

  /// Moves the assessment one step forward in its linear lifecycle
  /// (`DRAFT → PUBLISHED → ACTIVE → SCORING_LOCKED → CLOSED → ARCHIVED`).
  /// Fails with [IllegalStateTransitionFailure] for anything other than the
  /// single legal next step, and moving to `ACTIVE` additionally requires a
  /// published answer key.
  Future<Result<Assessment>> setAssessmentStatus(
    String assessmentId,
    AssessmentStatus next,
  );

  Future<Result<List<AssessmentQuestion>>> listQuestions(String assessmentId);

  /// Updates one question's marks/topic/difficulty/option override. Only
  /// while the assessment is still `DRAFT` — once published, the paper is
  /// printed and its questions cannot be silently renumbered or reweighted.
  Future<Result<AssessmentQuestion>> updateQuestion({
    required String assessmentId,
    required int questionNumber,
    double? marks,
    String? topic,
    String? difficulty,
    List<String>? options,
  });

  Future<Result<List<AnswerKey>>> listAnswerKeyVersions(String assessmentId);

  Future<Result<AnswerKey?>> getPublishedAnswerKey(String assessmentId);

  /// Publishes a new answer-key version.
  ///
  /// The first version needs no [changeReason] and publishes directly. Every
  /// version after that is a correction: [changeReason] is mandatory, and
  /// publishing it marks the previously published version `SUPERSEDED`.
  /// There is no separate "update" method — a key is never edited in place,
  /// only superseded by the next version (docs/02-data-model.md Critical
  /// Rules 5-6).
  Future<Result<AnswerKey>> publishAnswerKey({
    required String assessmentId,
    required Map<int, String> answers,
    String? publishedBy,
    String? changeReason,
  });

  /// Lists assignments, restricted to schools [scope] covers.
  Future<Result<Page<AssessmentAssignment>>> listAssignments({
    required AccessScope scope,
    String? assessmentId,
    PageRequest request = PageRequest.first,
  });

  Future<Result<AssessmentAssignment>> createAssignment({
    required String assessmentId,
    required String schoolId,
    required String grade,
    required List<String> sections,
    required List<String> assignedTeacherIds,
    required int expectedStudentCount,
    DateTime? dueDate,
  });

  Future<Result<AssessmentAssignment>> setAssignmentStatus(
    String assignmentId,
    AssignmentStatus next,
  );
}
