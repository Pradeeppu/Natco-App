/// Assessments: paginated, searchable, scope-filtered list.
///
/// Visibility comes from an assessment's *assignments*, not from the
/// assessment itself — the same paper is sat across several states — so a
/// Supervisor sees the papers their own schools are sitting.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/paged_list_controller.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/core/widgets/status_chip.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/presentation/controller/assessment_controllers.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';

/// Colour for each lifecycle state.
///
/// Draft is `pending` rather than `neutral` on purpose: a draft is unfinished
/// work, and the list is where someone notices it has been sitting that way.
StatusTone assessmentTone(AssessmentStatus status) => switch (status) {
  AssessmentStatus.draft => StatusTone.pending,
  AssessmentStatus.published => StatusTone.success,
  AssessmentStatus.active => StatusTone.success,
  AssessmentStatus.closed => StatusTone.neutral,
  AssessmentStatus.archived => StatusTone.neutral,
};

final class AssessmentsScreen extends ConsumerStatefulWidget {
  const AssessmentsScreen({super.key});

  @override
  ConsumerState<AssessmentsScreen> createState() => _AssessmentsScreenState();
}

class _AssessmentsScreenState extends ConsumerState<AssessmentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  AssessmentStatus? _status;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 240) {
      ref.read(assessmentListControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SessionState session = ref.watch(sessionProvider);
    final bool canManage = session.authorization.can(
      Permission.manageAssessments,
    );
    final AsyncValue<PagedListState<Assessment>> value = ref.watch(
      assessmentListControllerProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Assessments')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.push(RoutePaths.assessmentNew),
              icon: const Icon(Icons.post_add_outlined),
              label: const Text('New assessment'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search by name or subject',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (String q) => ref
                    .read(assessmentListControllerProvider.notifier)
                    .setQuery(q),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('All'),
                      selected: _status == null,
                      onSelected: (_) => _setStatus(null),
                    ),
                  ),
                  for (final AssessmentStatus status in AssessmentStatus.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(status.displayName),
                        selected: _status == status,
                        onSelected: (_) => _setStatus(status),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: value.when(
                loading: () => const LoadingView(),
                error: (Object error, StackTrace _) => FailureView(
                  failure: asFailure(error),
                  onRetry: () => ref
                      .read(assessmentListControllerProvider.notifier)
                      .refresh(),
                ),
                data: (PagedListState<Assessment> state) {
                  final Failure? failure = state.failure;
                  if (failure != null) {
                    return FailureView(
                      failure: failure,
                      onRetry: () => ref
                          .read(assessmentListControllerProvider.notifier)
                          .refresh(),
                    );
                  }
                  if (state.items.isEmpty) {
                    return const EmptyView(
                      title: 'No assessments found',
                      message:
                          'Assessments appear here once they are assigned to a '
                          'school in your area.',
                      icon: Icons.assignment_outlined,
                    );
                  }
                  return ListView.separated(
                    controller: _scrollController,
                    itemCount: state.items.length + (state.hasMore ? 1 : 0),
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      if (index >= state.items.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            ),
                          ),
                        );
                      }
                      return _AssessmentTile(assessment: state.items[index]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setStatus(AssessmentStatus? status) {
    setState(() => _status = status);
    ref
        .read(assessmentListControllerProvider.notifier)
        .setStatusFilter(status);
  }
}

final class _AssessmentTile extends StatelessWidget {
  const _AssessmentTile({required this.assessment});

  final Assessment assessment;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      title: Text(assessment.assessmentName),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              'Grade ${assessment.grade} - ${assessment.subject} - '
              '${assessment.totalQuestions} questions',
              style: theme.textTheme.bodySmall,
            ),
            StatusChip(
              label: assessment.status.displayName,
              tone: assessmentTone(assessment.status),
            ),
            // "No answer key" is a real, actionable state, not an empty
            // field: an assessment cannot be sat without one, so it is
            // shown rather than left blank.
            StatusChip(
              label: assessment.hasPublishedKey
                  ? 'Key v${assessment.publishedAnswerKeyVersion}'
                  : 'No answer key',
              tone: assessment.hasPublishedKey
                  ? StatusTone.neutral
                  : StatusTone.warning,
            ),
          ],
        ),
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(
        RoutePaths.of(RoutePaths.assessmentDetail, <String, String>{
          'assessmentId': assessment.assessmentId,
        }),
      ),
    );
  }
}
