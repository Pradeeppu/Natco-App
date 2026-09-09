/// Results list for one assessment.
///
/// Reads `assessmentId` from the query string — the same convention
/// `StudentsScreen` uses for its school filter — because there is nowhere
/// else for it to come from short of a free-typed field, which requirement
/// §10 forbids. `AssessmentDetailScreen`'s "View results" button is the one
/// real entry point; opening `/results` with nothing selected asks the user
/// to go back and choose an assessment rather than guessing one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/paged_list_controller.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/presentation/controller/assessment_controllers.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/results/domain/entity/assessment_result.dart';
import 'package:natco_app/features/results/presentation/controller/result_controllers.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/presentation/controller/student_list_controller.dart';

final class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key});

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  final ScrollController _scrollController = ScrollController();
  String? _assessmentId;
  bool _initialised = false;
  bool _scoring = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 240) {
      ref.read(resultListControllerProvider.notifier).loadMore();
    }
  }

  void _ensureInitialised(BuildContext context) {
    if (_initialised) {
      return;
    }
    _initialised = true;
    final String? assessmentId = GoRouterState.of(
      context,
    ).uri.queryParameters['assessmentId'];
    if (assessmentId == null) {
      return;
    }
    _assessmentId = assessmentId;
    // Both calls mutate provider state, which Riverpod refuses mid-build —
    // deferred to after this frame, matching `StudentsScreen`'s
    // `_ensureInitialFilter`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(resultListControllerProvider.notifier).setAssessment(assessmentId);
      _ensureScored();
    });
  }

  Future<void> _ensureScored() async {
    final String? assessmentId = _assessmentId;
    final SessionState? session = mounted ? ref.read(sessionProvider) : null;
    final String? actorUserId = session?.authorization.user?.userId;
    final String? actorRole = session?.authorization.user?.role.wireName;
    if (assessmentId == null || actorUserId == null || actorRole == null) {
      return;
    }
    setState(() => _scoring = true);
    await ref
        .read(resultRepositoryProvider)
        .ensureScored(
          assessmentId: assessmentId,
          scope:
              session!.authorization.user?.scope ??
              const AccessScope(level: ScopeLevel.school),
          actorUserId: actorUserId,
          actorRole: actorRole,
        );
    if (!mounted) {
      return;
    }
    setState(() => _scoring = false);
    await ref.read(resultListControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    _ensureInitialised(context);
    final ThemeData theme = Theme.of(context);

    if (_assessmentId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Results')),
        body: const SafeArea(
          child: EmptyView(
            title: 'Open an assessment to see its results',
            message:
                'Go to Assessments, choose one, and use "View results" from '
                'its detail screen.',
            icon: Icons.grading_outlined,
          ),
        ),
      );
    }

    final String assessmentId = _assessmentId!;
    final AsyncValue<PagedListState<AssessmentResult>> value = ref.watch(
      resultListControllerProvider,
    );
    final AsyncValue<Assessment> assessmentValue = ref.watch(
      assessmentProvider(assessmentId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            assessmentValue.maybeWhen(
              data: (Assessment assessment) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  '${assessment.assessmentName} · '
                  '${assessment.subject} · Grade ${assessment.grade}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
            if (_scoring)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: LinearProgressIndicator(),
              ),
            Expanded(
              child: value.when(
                loading: () => const LoadingView(),
                error: (Object error, StackTrace _) => FailureView(
                  failure: asFailure(error),
                  onRetry: () =>
                      ref.read(resultListControllerProvider.notifier).refresh(),
                ),
                data: (PagedListState<AssessmentResult> state) {
                  final Failure? failure = state.failure;
                  if (failure != null) {
                    return FailureView(
                      failure: failure,
                      onRetry: () => ref
                          .read(resultListControllerProvider.notifier)
                          .refresh(),
                    );
                  }
                  if (state.items.isEmpty) {
                    return EmptyView(
                      title: 'No results yet',
                      message: _scoring
                          ? 'Scoring the sheets that are ready...'
                          : 'Nobody\'s sheet on this assessment has finished '
                                'validation yet.',
                      icon: Icons.grading_outlined,
                    );
                  }
                  return _ResultsBody(
                    assessmentId: assessmentId,
                    state: state,
                    scrollController: _scrollController,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ResultsBody extends StatelessWidget {
  const _ResultsBody({
    required this.assessmentId,
    required this.state,
    required this.scrollController,
  });

  final String assessmentId;
  final PagedListState<AssessmentResult> state;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;
    final List<AssessmentResult> items = state.items;
    final double average =
        items.map((AssessmentResult r) => r.percentage).reduce((a, b) => a + b) /
        items.length;
    final double highest = items
        .map((AssessmentResult r) => r.percentage)
        .reduce((a, b) => a > b ? a : b);
    final double lowest = items
        .map((AssessmentResult r) => r.percentage)
        .reduce((a, b) => a < b ? a : b);

    Color toneFor(double pct) => pct >= 60
        ? status.success
        : pct >= 40
        ? status.warning
        : status.danger;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: <Widget>[
              _Metric(label: 'Scored', value: '${items.length}'),
              _Metric(
                label: 'Average',
                value: '${average.round()}%',
                color: toneFor(average),
              ),
              _Metric(label: 'Highest', value: '${highest.round()}%'),
              _Metric(label: 'Lowest', value: '${lowest.round()}%'),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            controller: scrollController,
            itemCount: items.length + (state.hasMore ? 1 : 0),
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              if (index >= items.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                );
              }
              final AssessmentResult result = items[index];
              return Consumer(
                builder: (BuildContext context, WidgetRef ref, _) {
                  final AsyncValue<Student> student = ref.watch(
                    studentProvider(result.studentId),
                  );
                  return ListTile(
                    title: Text(
                      student.maybeWhen(
                        data: (Student s) => s.studentName,
                        orElse: () => 'Loading...',
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(3),
                        ),
                        child: LinearProgressIndicator(
                          value: (result.percentage / 100).clamp(0, 1),
                          minHeight: 6,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          color: toneFor(result.percentage),
                        ),
                      ),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          '${result.marksObtained.toStringAsFixed(0)}/'
                          '${result.totalMarks.toStringAsFixed(0)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: toneFor(result.percentage),
                          ),
                        ),
                        Text(
                          '${result.percentage.round()}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    onTap: () => context.push(
                      '${RoutePaths.of(RoutePaths.studentResult, <String, String>{
                        'studentId': result.studentId,
                      })}?assessmentId=$assessmentId',
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

final class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

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
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
