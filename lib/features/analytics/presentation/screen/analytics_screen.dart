/// Analytics for one assessment, scoped to the caller.
///
/// Reads `assessmentId` from the query string, the same convention
/// `ResultsScreen` uses — there is nowhere else for it to come from short of
/// a free-typed field (requirement §10), and `AssessmentDetailScreen` is the
/// real entry point.
///
/// Every figure here is computed from real `AssessmentResult`/`OmrAnswer`
/// records (`LiveAnalyticsRepositoryImpl`), scoped to the caller's own
/// `AccessScope` exactly like every other list in the app — a Supervisor's
/// numbers never include a school outside their clusters.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/analytics/domain/entity/question_analytics.dart';
import 'package:natco_app/features/analytics/presentation/controller/analytics_controllers.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/presentation/controller/assessment_controllers.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

final class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? assessmentId = GoRouterState.of(
      context,
    ).uri.queryParameters['assessmentId'];

    if (assessmentId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Analytics')),
        body: const SafeArea(
          child: EmptyView(
            title: 'Open an assessment to see its analytics',
            message:
                'Go to Assessments, choose one, and use "View analytics" from '
                'its detail screen.',
            icon: Icons.insights_outlined,
          ),
        ),
      );
    }

    final AccessScope scope =
        ref.watch(sessionProvider).authorization.user?.scope ??
        const AccessScope(level: ScopeLevel.school);
    final ({String assessmentId, AccessScope scope}) key = (
      assessmentId: assessmentId,
      scope: scope,
    );

    final AsyncValue<AssessmentAnalyticsSummary> summaryValue = ref.watch(
      analyticsSummaryProvider(key),
    );
    final AsyncValue<List<QuestionAnalytics>> questionsValue = ref.watch(
      questionAnalyticsProvider(key),
    );
    final AsyncValue<Assessment> assessmentValue = ref.watch(
      assessmentProvider(assessmentId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: SafeArea(
        child: summaryValue.when(
          loading: () => const LoadingView(),
          error: (Object error, StackTrace _) => FailureView(
            failure: asFailure(error),
            onRetry: () => ref.invalidate(analyticsSummaryProvider(key)),
          ),
          data: (AssessmentAnalyticsSummary summary) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              assessmentValue.maybeWhen(
                data: (Assessment a) => Text(
                  '${a.assessmentName} · ${a.subject} · Grade ${a.grade}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),
              _SummaryMetrics(summary: summary),
              const SizedBox(height: 24),
              Text(
                'Question performance',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                '% answering correctly, from every scored sheet in your scope',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              questionsValue.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (Object error, StackTrace _) =>
                    FailureView(failure: asFailure(error)),
                data: (List<QuestionAnalytics> questions) =>
                    questions.isEmpty
                    ? const EmptyView(
                        title: 'Nothing scored yet',
                        message:
                            'Question performance appears once at least one '
                            'sheet in your scope has been scored.',
                        icon: Icons.query_stats_outlined,
                      )
                    : _QuestionPerformanceCard(questions: questions),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SummaryMetrics extends StatelessWidget {
  const _SummaryMetrics({required this.summary});

  final AssessmentAnalyticsSummary summary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _Metric(
                  label: 'Scored',
                  value: '${summary.scoredCount}',
                  caption: 'of ${summary.expectedCount} expected',
                ),
                _Metric(
                  label: 'Completion',
                  value: '${summary.completionPercentage.round()}%',
                  color: summary.completionPercentage >= 80
                      ? status.success
                      : status.warning,
                ),
                _Metric(
                  label: 'Average',
                  value: '${summary.averagePercentage.round()}%',
                ),
              ],
            ),
            const Divider(height: 28),
            Row(
              children: <Widget>[
                _Metric(
                  label: 'Highest',
                  value: '${summary.highestPercentage.round()}%',
                  color: status.success,
                ),
                _Metric(
                  label: 'Lowest',
                  value: '${summary.lowestPercentage.round()}%',
                  color: status.danger,
                ),
                _Metric(
                  label: 'Awaiting validation',
                  value: '${summary.needsValidationCount}',
                  color: summary.needsValidationCount > 0
                      ? status.warning
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color, this.caption});

  final String label;
  final String value;
  final Color? color;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(color: color),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (caption != null)
            Text(
              caption!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

final class _QuestionPerformanceCard extends StatelessWidget {
  const _QuestionPerformanceCard({required this.questions});

  final List<QuestionAnalytics> questions;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;

    Color toneFor(double pct) => pct >= 60
        ? status.success
        : pct >= 40
        ? status.warning
        : status.danger;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: questions
              .map(
                (QuestionAnalytics q) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 36,
                        child: Text('Q${q.questionNumber}',
                            style: theme.textTheme.bodySmall),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(3),
                          ),
                          child: LinearProgressIndicator(
                            value: (q.correctPercentage / 100).clamp(0, 1),
                            minHeight: 8,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            color: toneFor(q.correctPercentage),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 42,
                        child: Text(
                          '${q.correctPercentage.round()}%',
                          textAlign: TextAlign.right,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}
