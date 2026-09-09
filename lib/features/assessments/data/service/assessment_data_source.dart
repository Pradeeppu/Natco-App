/// Backend-swappable raw storage for assessments, answer keys and
/// assignments.
///
/// CRUD and paged queries only. Policy (Critical Rule 7's immutability), audit
/// logging and version arithmetic live once in `AssessmentRepositoryImpl`.
library;

import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

abstract interface class AssessmentDataSource {
  Future<Result<Page<Assessment>>> listAssessments({
    required AccessScope scope,
    String query = '',
    AssessmentStatus? status,
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  Future<Result<Assessment>> getAssessment(String assessmentId);

  Future<Result<Assessment>> createAssessment(Assessment assessment);

  Future<Result<Assessment>> updateAssessment(Assessment assessment);

  Future<Result<List<AnswerKey>>> listAnswerKeys(String assessmentId);

  Future<Result<AnswerKey>> saveAnswerKey(AnswerKey key);

  /// Publishes [key] and points its assessment at that version, in one
  /// atomic step.
  ///
  /// Atomicity is the whole point of the method existing: an assessment
  /// pointing at an unpublished key, or a published key no assessment points
  /// at, would each let sheets be scored against something nobody approved.
  /// The Firestore implementation does this in a transaction; the in-memory
  /// one does both writes before returning.
  Future<Result<AnswerKey>> publishAnswerKey(AnswerKey key);

  Future<Result<List<AssessmentAssignment>>> listAssignments(
    String assessmentId,
  );

  Future<Result<AssessmentAssignment>> saveAssignment(
    AssessmentAssignment assignment,
  );

  Future<Result<void>> deleteAssignment(String assignmentId);
}
