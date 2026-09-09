/// Assessments and their versioned answer keys (docs/02-data-model.md §4-5).
///
/// Follows the conventions the earlier phases set: `list*` takes the caller's
/// own [AccessScope] so filtering happens in the query, and mutations take
/// `actorUserId`/`actorRole` for the audit entry.
library;

import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

abstract interface class AssessmentRepository {
  /// Assessments visible to [scope].
  ///
  /// An assessment is not itself geographic — the same paper is sat across
  /// several states — so visibility comes from its *assignments*. Passing the
  /// scope here lets the data source join the two rather than making every
  /// caller do it.
  Future<Result<Page<Assessment>>> listAssessments({
    required AccessScope scope,
    String query = '',
    AssessmentStatus? status,
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  Future<Result<Assessment>> getAssessment(String assessmentId);

  Future<Result<Assessment>> createAssessment(
    Assessment assessment, {
    required String actorUserId,
    required String actorRole,
  });

  /// Updates a **draft** assessment's fields.
  ///
  /// Refused once published: `totalQuestions` and `marksPerQuestion` are what
  /// every score was computed from, and changing them under existing results
  /// would silently rewrite marks that nobody re-derived.
  Future<Result<Assessment>> updateAssessment(
    Assessment assessment, {
    required String actorUserId,
    required String actorRole,
  });

  /// Moves an assessment through its lifecycle, refusing illegal transitions.
  Future<Result<Assessment>> changeStatus(
    String assessmentId, {
    required AssessmentStatus next,
    required String actorUserId,
    required String actorRole,
  });

  // ------------------------------------------------------------ answer keys

  /// Every version, newest first, so the history is visible rather than
  /// implied.
  Future<Result<List<AnswerKey>>> listAnswerKeyVersions(String assessmentId);

  /// The version currently in force, or `null` when none is published yet.
  Future<Result<AnswerKey?>> getPublishedAnswerKey(String assessmentId);

  /// A specific version — what a result names when it records how it was
  /// scored.
  Future<Result<AnswerKey>> getAnswerKeyVersion(
    String assessmentId, {
    required int version,
  });

  /// The unpublished draft, creating v1 if none exists.
  Future<Result<AnswerKey>> getOrCreateDraftAnswerKey(
    String assessmentId, {
    required String actorUserId,
  });

  /// Saves an edit to an unpublished draft. Refused for a published version
  /// (Critical Rule 7).
  Future<Result<AnswerKey>> saveDraftAnswerKey(
    AnswerKey key, {
    required String actorUserId,
    required String actorRole,
  });

  /// Publishes [key], freezing it and pointing the assessment at its version.
  ///
  /// Both writes happen together: an assessment pointing at an unpublished key,
  /// or a published key no assessment points at, would each let sheets be
  /// scored against something nobody approved.
  Future<Result<AnswerKey>> publishAnswerKey(
    AnswerKey key, {
    required String actorUserId,
    required String actorRole,
  });

  /// Opens a correction: a new unpublished version carrying the current
  /// answers forward, with the reason recorded.
  Future<Result<AnswerKey>> startCorrection(
    String assessmentId, {
    required String changeReason,
    required String actorUserId,
    required String actorRole,
  });

  // ------------------------------------------------------------ assignments

  Future<Result<List<AssessmentAssignment>>> listAssignments(
    String assessmentId,
  );

  Future<Result<AssessmentAssignment>> assign(
    AssessmentAssignment assignment, {
    required String actorUserId,
    required String actorRole,
  });

  Future<Result<void>> unassign(
    String assignmentId, {
    required String actorUserId,
    required String actorRole,
  });
}
