/// Analytics rollups: a scope-level summary and per-question performance,
/// both scoped exactly like every other list in the app — a Supervisor's
/// numbers never include a school outside their clusters (docs/02-data-model.md
/// §7, docs/08-mvp-implementation-plan.md phase 10 exit criteria).
library;

import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/analytics/domain/entity/question_analytics.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

abstract interface class AnalyticsRepository {
  Future<Result<AssessmentAnalyticsSummary>> getSummary({
    required String assessmentId,
    required AccessScope scope,
  });

  /// Ordered by question number.
  Future<Result<List<QuestionAnalytics>>> getQuestionAnalytics({
    required String assessmentId,
    required AccessScope scope,
  });
}
