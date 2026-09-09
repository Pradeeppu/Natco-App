/// The searchable, paginated list of assessment definitions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_status.dart';
import 'package:natco_app/features/assessments/presentation/controller/assessments_list_controller.dart';
import 'package:natco_app/features/assessments/presentation/widget/assessment_form_dialog.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';

final class AssessmentsScreen extends ConsumerStatefulWidget {
  const AssessmentsScreen({super.key});

  @override
  ConsumerState<AssessmentsScreen> createState() => _AssessmentsScreenState();
}

class _AssessmentsScreenState extends ConsumerState<AssessmentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 240) {
      ref.read(assessmentsListProvider.notifier).loadMore();
    }
  }

  Future<void> _createAssessment() async {
    await showAssessmentFormDialog(
      context: context,
      onSubmit: (AssessmentDraft draft) async {
        final result = await ref
            .read(assessmentsRepositoryProvider)
            .createAssessment(
              assessmentName: draft.assessmentName,
              assessmentCode: draft.assessmentCode,
              academicYear: draft.academicYear,
              grade: draft.grade,
              subject: draft.subject,
              questionCount: draft.questionCount,
              questionType: kDefaultQuestionType,
              options: draft.options,
              durationMinutes: draft.durationMinutes,
              instructions: draft.instructions,
            );
        return result.failureOrNull;
      },
    );
    if (mounted) {
      await ref.read(assessmentsListProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AssessmentsListState state = ref.watch(assessmentsListProvider);
    final bool canManage = ref
        .watch(sessionProvider)
        .authorization
        .can(Permission.manageAssessments);

    return Scaffold(
      appBar: AppBar(title: const Text('Assessments')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search assessments',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (String value) =>
                    ref.read(assessmentsListProvider.notifier).search(value),
              ),
            ),
            _StatusFilterRow(status: state.status),
            Expanded(child: _buildBody(state)),
          ],
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _createAssessment,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
    );
  }

  Widget _buildBody(AssessmentsListState state) {
    if (state.isLoading && state.assessments.isEmpty) {
      return const LoadingView();
    }
    if (state.failure != null && state.assessments.isEmpty) {
      return FailureView(
        failure: state.failure!,
        onRetry: () => ref.read(assessmentsListProvider.notifier).refresh(),
      );
    }
    if (state.assessments.isEmpty) {
      return EmptyView(
        title: 'No assessments found',
        message: state.query.isEmpty
            ? 'No assessments have been created yet.'
            : 'No results for "${state.query}".',
        icon: Icons.assignment_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(assessmentsListProvider.notifier).refresh(),
      child: ListView.separated(
        controller: _scrollController,
        itemCount: state.assessments.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          if (index >= state.assessments.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final Assessment assessment = state.assessments[index];
          return ListTile(
            leading: const Icon(Icons.assignment_outlined),
            title: Text(assessment.assessmentName),
            subtitle: Text(
              '${assessment.assessmentCode} · Grade ${assessment.grade} · '
              '${assessment.subject} · ${assessment.status.displayName}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(
              RoutePaths.of(RoutePaths.assessmentDetail, <String, String>{
                'assessmentId': assessment.assessmentId,
              }),
            ),
          );
        },
      ),
    );
  }
}

final class _StatusFilterRow extends ConsumerWidget {
  const _StatusFilterRow({required this.status});

  final AssessmentStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          ChoiceChip(
            label: const Text('All'),
            selected: status == null,
            onSelected: (_) =>
                ref.read(assessmentsListProvider.notifier).filterByStatus(null),
          ),
          const SizedBox(width: 8),
          for (final AssessmentStatus option in AssessmentStatus.values) ...<Widget>[
            ChoiceChip(
              label: Text(option.displayName),
              selected: status == option,
              onSelected: (_) => ref
                  .read(assessmentsListProvider.notifier)
                  .filterByStatus(option),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    ),
  );
}
