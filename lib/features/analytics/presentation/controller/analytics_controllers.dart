/// Providers for the analytics screen. Both are keyed by (assessmentId,
/// scope) — a record, since Riverpod family parameters need only be `==`
/// comparable and `AccessScope` already implements that.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/analytics/domain/entity/question_analytics.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

final analyticsSummaryProvider =
    FutureProvider.family<
      AssessmentAnalyticsSummary,
      ({String assessmentId, AccessScope scope})
    >((Ref ref, ({String assessmentId, AccessScope scope}) key) async {
      final Result<AssessmentAnalyticsSummary> result = await ref
          .watch(analyticsRepositoryProvider)
          .getSummary(assessmentId: key.assessmentId, scope: key.scope);
      return switch (result) {
        Success<AssessmentAnalyticsSummary>(:final value) => value,
        FailureResult<AssessmentAnalyticsSummary>(:final failure) =>
          throw failure,
      };
    });

final questionAnalyticsProvider =
    FutureProvider.family<
      List<QuestionAnalytics>,
      ({String assessmentId, AccessScope scope})
    >((Ref ref, ({String assessmentId, AccessScope scope}) key) async {
      final Result<List<QuestionAnalytics>> result = await ref
          .watch(analyticsRepositoryProvider)
          .getQuestionAnalytics(assessmentId: key.assessmentId, scope: key.scope);
      return switch (result) {
        Success<List<QuestionAnalytics>>(:final value) => value,
        FailureResult<List<QuestionAnalytics>>(:final failure) => throw failure,
      };
    });
