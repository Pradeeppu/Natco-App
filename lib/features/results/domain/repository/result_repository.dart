/// Scores: computing them, and reading them back
/// (docs/02-data-model.md §7, Critical Rule 5).
library;

import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/results/domain/entity/assessment_result.dart';

abstract interface class ResultRepository {
  /// Current (non-superseded) results for [assessmentId], scope-filtered.
  Future<Result<Page<AssessmentResult>>> listResults({
    required String assessmentId,
    required AccessScope scope,
    Object? cursor,
    int pageSize = kDefaultPageSize,
  });

  /// The current result for one student on one assessment, or `null` if
  /// their sheet has not been scored yet.
  Future<Result<AssessmentResult?>> getResultForStudent({
    required String assessmentId,
    required String studentId,
  });

  /// Scores one submission and writes the result.
  ///
  /// If a non-superseded result already exists for this [omrId] — a
  /// re-score after an answer-key correction, or after a late validation
  /// decision — it is marked superseded and a new row is written; the old
  /// row's scored fields are never changed (Critical Rule 5).
  Future<Result<AssessmentResult>> scoreSubmission(
    String omrId, {
    required String actorUserId,
    required String actorRole,
  });

  /// Scores every submission under [assessmentId] that is ready for scoring
  /// and does not already have a current result — the "open the results
  /// screen and it fills in" behaviour a teacher expects once validation is
  /// done. Already-scored submissions are left untouched; this is not a
  /// re-score sweep.
  Future<Result<int>> ensureScored({
    required String assessmentId,
    required AccessScope scope,
    required String actorUserId,
    required String actorRole,
  });
}
