/// Backend-swappable raw storage for results.
///
/// Mirrors `StudentDataSource`: CRUD and paged queries only. Scoring,
/// supersession and audit logging live once in `ResultRepositoryImpl`.
library;

import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/results/domain/entity/assessment_result.dart';

abstract interface class ResultDataSource {
  Future<Result<Page<AssessmentResult>>> listResults({
    required String assessmentId,
    required AccessScope scope,
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  /// The current (non-superseded) result for [studentId] on [assessmentId],
  /// or `null` if none exists yet.
  Future<Result<AssessmentResult?>> getCurrentResultForStudent({
    required String assessmentId,
    required String studentId,
  });

  /// The current (non-superseded) result for [omrId], or `null`.
  Future<Result<AssessmentResult?>> getCurrentResultForSubmission(String omrId);

  Future<Result<AssessmentResult>> saveResult(AssessmentResult result);
}
