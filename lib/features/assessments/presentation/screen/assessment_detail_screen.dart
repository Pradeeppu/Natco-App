/// One assessment: its shape, its answer-key history, and where it is being
/// sat.
///
/// The answer-key history is shown in full rather than only the current
/// version. A correction is only meaningful next to what it replaced, and
/// hiding superseded versions would make "why did this child's mark change?"
/// unanswerable from the UI — which is the whole point of versioning the key
/// (Critical Rule 7).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/core/widgets/status_chip.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/assessments/presentation/controller/assessment_controllers.dart';
import 'package:natco_app/features/assessments/presentation/screen/assessments_screen.dart'
    show assessmentTone;
import 'package:natco_app/features/auth/domain/entity/app_user.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';

final class AssessmentDetailScreen extends ConsumerWidget {
  const AssessmentDetailScreen({required this.assessmentId, super.key});

  final String assessmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Assessment> value = ref.watch(
      assessmentProvider(assessmentId),
    );
    final SessionState session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Assessment')),
      body: SafeArea(
        child: value.when(
          loading: () => const LoadingView(),
          error: (Object error, StackTrace _) => FailureView(
            failure: asFailure(error),
            onRetry: () => ref.invalidate(assessmentProvider(assessmentId)),
          ),
          data: (Assessment assessment) => _Body(
            assessment: assessment,
            session: session,
          ),
        ),
      ),
    );
  }
}

final class _Body extends ConsumerWidget {
  const _Body({required this.assessment, required this.session});

  final Assessment assessment;
  final SessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool canManageKey = session.authorization.can(
      Permission.manageAnswerKey,
    );
    final bool canChangeStatus = session.authorization.can(
      Permission.manageAssessmentStatus,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Text(
          assessment.assessmentName,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            StatusChip(
              label: assessment.status.displayName,
              tone: assessmentTone(assessment.status),
            ),
            StatusChip(
              label: assessment.hasPublishedKey
                  ? 'Answer key v${assessment.publishedAnswerKeyVersion}'
                  : 'No answer key',
              tone: assessment.hasPublishedKey
                  ? StatusTone.neutral
                  : StatusTone.warning,
            ),
          ],
        ),
        if (!assessment.isReadyForSessions) ...<Widget>[
          const SizedBox(height: 16),
          InfoBanner(
            message: _notReadyMessage(assessment),
            icon: Icons.info_outline,
            isWarning: true,
          ),
        ],
        const Divider(height: 32),
        _Row(label: 'Academic year', value: assessment.academicYear),
        _Row(label: 'Grade', value: assessment.grade),
        _Row(label: 'Subject', value: assessment.subject),
        _Row(
          label: 'Questions',
          value:
              '${assessment.totalQuestions} '
              '(${_marks(assessment.marksPerQuestion)} each, '
              '${_marks(assessment.totalMarks)} total)',
        ),
        if (assessment.negativeMarkPerWrongAnswer > 0)
          _Row(
            label: 'Negative marking',
            value:
                '-${_marks(assessment.negativeMarkPerWrongAnswer)} per wrong '
                'answer',
          ),
        _Row(label: 'OMR template', value: assessment.omrTemplateId),
        if (assessment.description != null)
          _Row(label: 'Notes', value: assessment.description!),

        const Divider(height: 32),
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Answer key', style: theme.textTheme.titleMedium),
            ),
            if (canManageKey)
              TextButton.icon(
                onPressed: () => context.push(
                  RoutePaths.of(RoutePaths.answerKey, <String, String>{
                    'assessmentId': assessment.assessmentId,
                  }),
                ),
                icon: const Icon(Icons.edit_outlined),
                label: Text(
                  assessment.hasPublishedKey ? 'Open' : 'Set answers',
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _AnswerKeyHistory(assessmentId: assessment.assessmentId),

        const Divider(height: 32),
        Text('Where it is being sat', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _Assignments(assessmentId: assessment.assessmentId),

        if (session.authorization.can(Permission.viewResults)) ...<Widget>[
          const Divider(height: 32),
          OutlinedButton.icon(
            onPressed: () => context.push(
              '${RoutePaths.results}?assessmentId=${assessment.assessmentId}',
            ),
            icon: const Icon(Icons.grading_outlined),
            label: const Text('View results'),
          ),
        ],

        if (canChangeStatus && assessment.status.allowedNext.isNotEmpty) ...[
          const Divider(height: 32),
          Text('Move this assessment on', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            // Stated plainly because the transitions are one-way: a published
            // assessment that could quietly return to draft is one whose
            // answer key could be rewritten under results already scored.
            'These changes cannot be undone.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: assessment.status.allowedNext
                .map(
                  (AssessmentStatus next) => OutlinedButton(
                    onPressed: () => _confirmStatus(context, ref, next),
                    child: Text('Mark ${next.displayName.toLowerCase()}'),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmStatus(
    BuildContext context,
    WidgetRef ref,
    AssessmentStatus next,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Mark ${next.displayName.toLowerCase()}?'),
        content: Text(_transitionWarning(assessment.status, next)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(next.displayName),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) {
      return;
    }
    final AppUser? actor = ref.read(sessionProvider).authorization.user;
    if (actor == null) {
      return;
    }
    final Result<Assessment> result = await ref
        .read(assessmentRepositoryProvider)
        .changeStatus(
          assessment.assessmentId,
          next: next,
          actorUserId: actor.userId,
          actorRole: actor.role.wireName,
        );
    if (!context.mounted) {
      return;
    }
    result.fold(
      onSuccess: (_) {
        ref.invalidate(assessmentProvider(assessment.assessmentId));
        ref.read(assessmentListControllerProvider.notifier).refresh();
      },
      onFailure: (Failure failure) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.userMessage))),
    );
  }

  static String _notReadyMessage(Assessment assessment) {
    if (!assessment.hasPublishedKey) {
      return 'No answer key is published yet. Sessions cannot start until one '
          'is — without a key, every sheet would score zero.';
    }
    return 'This assessment is ${assessment.status.displayName.toLowerCase()}, '
        'so no new sheets can be captured against it.';
  }

  static String _transitionWarning(
    AssessmentStatus from,
    AssessmentStatus to,
  ) => switch (to) {
    AssessmentStatus.published =>
      'Teachers will be able to start sessions against this assessment. Its '
          'questions and marks can no longer be edited.',
    AssessmentStatus.active => 'Sheets are being captured for this assessment.',
    AssessmentStatus.closed =>
      'No further sheets can be captured. Sheets already captured are kept and '
          'can still be validated and scored.',
    AssessmentStatus.archived =>
      'This assessment moves out of the working lists. Its results and images '
          'are kept.',
    AssessmentStatus.draft => 'Returning to draft is not possible.',
  };

  /// Trims a trailing `.0` so a whole mark reads as `1` rather than `1.0`.
  static String _marks(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';
}

final class _AnswerKeyHistory extends ConsumerWidget {
  const _AnswerKeyHistory({required this.assessmentId});

  final String assessmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AnswerKey>> value = ref.watch(
      answerKeyVersionsProvider(assessmentId),
    );
    final ThemeData theme = Theme.of(context);

    return value.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ),
      error: (Object error, StackTrace _) =>
          Text(asFailure(error).userMessage, style: theme.textTheme.bodySmall),
      data: (List<AnswerKey> versions) {
        if (versions.isEmpty) {
          return Text(
            'No answer key has been created yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: versions
              .map(
                (AnswerKey key) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            'Version ${key.version}',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(width: 8),
                          StatusChip(
                            label: key.isPublished ? 'Published' : 'Draft',
                            tone: key.isPublished
                                ? StatusTone.success
                                : StatusTone.pending,
                          ),
                        ],
                      ),
                      if (key.supersedesVersion != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Replaces version ${key.supersedesVersion}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (key.changeReason != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            key.changeReason!,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

final class _Assignments extends ConsumerWidget {
  const _Assignments({required this.assessmentId});

  final String assessmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AssessmentAssignment>> value = ref.watch(
      assessmentAssignmentsProvider(assessmentId),
    );
    final ThemeData theme = Theme.of(context);

    return value.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ),
      error: (Object error, StackTrace _) =>
          Text(asFailure(error).userMessage, style: theme.textTheme.bodySmall),
      data: (List<AssessmentAssignment> assignments) {
        if (assignments.isEmpty) {
          return Text(
            'Not assigned to any school yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: assignments
              .map(
                (AssessmentAssignment a) =>
                    _AssignmentRow(assignment: a),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

final class _AssignmentRow extends ConsumerWidget {
  const _AssignmentRow({required this.assignment});

  final AssessmentAssignment assignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final String schoolName =
        ref.watch(schoolNameProvider(assignment.schoolId)).value ??
        assignment.schoolId;
    final String sections = assignment.sections.isEmpty
        ? 'all sections'
        : 'section${assignment.sections.length > 1 ? "s" : ""} '
              '${assignment.sections.join(", ")}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.school_outlined, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(schoolName, style: theme.textTheme.bodyMedium),
                Text(
                  'Grade ${assignment.grade}, $sections',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
