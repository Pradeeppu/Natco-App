/// One assessment: its questions, its answer-key summary, and its
/// assignments.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/constants/route_paths.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key_status.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_question.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_status.dart';
import 'package:natco_app/features/assessments/presentation/controller/assessment_detail_provider.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/domain/service/authorization.dart';

final class AssessmentDetailScreen extends ConsumerWidget {
  const AssessmentDetailScreen({required this.assessmentId, super.key});

  final String assessmentId;

  Future<void> _advanceStatus(
    BuildContext context,
    WidgetRef ref,
    AssessmentStatus next,
  ) async {
    final result = await ref
        .read(assessmentsRepositoryProvider)
        .setAssessmentStatus(assessmentId, next);
    if (result.failureOrNull != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.failureOrNull!.userMessage)));
    }
    ref.invalidate(assessmentDetailProvider(assessmentId));
  }

  Future<void> _addAssignment(
    BuildContext context,
    WidgetRef ref,
    Assessment assessment,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => _AddAssignmentDialog(
        assessment: assessment,
        onSubmit: (String schoolId, List<String> sections, int expectedCount) async {
          final result = await ref
              .read(assessmentsRepositoryProvider)
              .createAssignment(
                assessmentId: assessment.assessmentId,
                schoolId: schoolId,
                grade: assessment.grade,
                sections: sections,
                assignedTeacherIds: const <String>[],
                expectedStudentCount: expectedCount,
              );
          return result.failureOrNull;
        },
      ),
    );
    ref.invalidate(assessmentAssignmentsProvider(assessmentId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Assessment?> async = ref.watch(
      assessmentDetailProvider(assessmentId),
    );
    final Authorization authorization = ref.watch(sessionProvider).authorization;

    return Scaffold(
      appBar: AppBar(title: const Text('Assessment')),
      body: SafeArea(
        child: async.when(
          loading: () => const LoadingView(),
          error: (Object error, StackTrace stackTrace) => FailureView(
            failure: error is AssessmentDetailFailure
                ? error.failure
                : const UnexpectedFailure(),
            onRetry: () => ref.invalidate(assessmentDetailProvider(assessmentId)),
          ),
          data: (Assessment? assessment) {
            if (assessment == null) {
              return const EmptyView(
                title: 'Assessment not found',
                icon: Icons.assignment_outlined,
              );
            }
            return _AssessmentDetailBody(
              assessment: assessment,
              authorization: authorization,
              onAdvanceStatus: (AssessmentStatus next) =>
                  _advanceStatus(context, ref, next),
              onAddAssignment: () => _addAssignment(context, ref, assessment),
            );
          },
        ),
      ),
    );
  }
}

final class _AssessmentDetailBody extends ConsumerWidget {
  const _AssessmentDetailBody({
    required this.assessment,
    required this.authorization,
    required this.onAdvanceStatus,
    required this.onAddAssignment,
  });

  final Assessment assessment;
  final Authorization authorization;
  final ValueChanged<AssessmentStatus> onAdvanceStatus;
  final VoidCallback onAddAssignment;

  AssessmentStatus? get _nextStatus {
    final int nextIndex = assessment.status.index + 1;
    return nextIndex < AssessmentStatus.values.length
        ? AssessmentStatus.values[nextIndex]
        : null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool canManageStatus = authorization.can(
      Permission.manageAssessmentStatus,
    );
    final bool canManageAnswerKey = authorization.can(Permission.manageAnswerKey);
    final bool canManageAssignments = authorization.can(
      Permission.manageAssignments,
    );
    final AssessmentStatus? next = _nextStatus;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(assessment.assessmentName, style: theme.textTheme.headlineSmall),
        Text(
          '${assessment.assessmentCode} · Grade ${assessment.grade} · '
          '${assessment.subject} · ${assessment.academicYear}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            Chip(label: Text(assessment.status.displayName)),
            Chip(label: Text('${assessment.questionCount} questions')),
            Chip(label: Text('${assessment.durationMinutes} min')),
            Chip(
              label: Text(
                assessment.activeAnswerKeyVersion == null
                    ? 'No answer key'
                    : 'Key v${assessment.activeAnswerKeyVersion}',
              ),
            ),
          ],
        ),
        if (canManageStatus && next != null) ...<Widget>[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => onAdvanceStatus(next),
            icon: const Icon(Icons.arrow_forward),
            label: Text('Move to ${next.displayName}'),
          ),
        ],
        const SizedBox(height: 24),
        Text('Answer key', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _AnswerKeySummary(assessmentId: assessment.assessmentId),
        if (canManageAnswerKey) ...<Widget>[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.go(
              RoutePaths.of(RoutePaths.answerKey, <String, String>{
                'assessmentId': assessment.assessmentId,
              }),
            ),
            icon: const Icon(Icons.key_outlined),
            label: const Text('Manage answer key'),
          ),
        ],
        const SizedBox(height: 24),
        Text('Questions', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _QuestionsSummary(assessmentId: assessment.assessmentId),
        const SizedBox(height: 24),
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Assignments', style: theme.textTheme.titleMedium),
            ),
            if (canManageAssignments)
              TextButton.icon(
                onPressed: onAddAssignment,
                icon: const Icon(Icons.add),
                label: const Text('Assign'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _AssignmentsList(assessmentId: assessment.assessmentId),
      ],
    );
  }
}

final class _AnswerKeySummary extends ConsumerWidget {
  const _AnswerKeySummary({required this.assessmentId});

  final String assessmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AnswerKey>> async = ref.watch(
      answerKeyVersionsProvider(assessmentId),
    );
    return async.when(
      loading: () => const SizedBox(
        height: 24,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (Object error, StackTrace stackTrace) => const Text('Unable to load.'),
      data: (List<AnswerKey> versions) {
        if (versions.isEmpty) {
          return const Text('No answer key has been published yet.');
        }
        final int published = versions
            .where((AnswerKey k) => k.status == AnswerKeyStatus.published)
            .length;
        return Text(
          '${versions.length} version${versions.length == 1 ? '' : 's'}'
          '${published == 0 ? ', none currently published' : ''}.',
        );
      },
    );
  }
}

final class _QuestionsSummary extends ConsumerWidget {
  const _QuestionsSummary({required this.assessmentId});

  final String assessmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AssessmentQuestion>> async = ref.watch(
      assessmentQuestionsProvider(assessmentId),
    );
    return async.when(
      loading: () => const SizedBox(
        height: 24,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (Object error, StackTrace stackTrace) => const Text('Unable to load.'),
      data: (List<AssessmentQuestion> questions) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final AssessmentQuestion question in questions)
            Chip(
              label: Text(
                'Q${question.questionNumber} (${question.marks.toStringAsFixed(0)}m)',
              ),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

final class _AssignmentsList extends ConsumerWidget {
  const _AssignmentsList({required this.assessmentId});

  final String assessmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AssessmentAssignment>> async = ref.watch(
      assessmentAssignmentsProvider(assessmentId),
    );
    return async.when(
      loading: () => const SizedBox(
        height: 24,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (Object error, StackTrace stackTrace) => const Text('Unable to load.'),
      data: (List<AssessmentAssignment> assignments) {
        if (assignments.isEmpty) {
          return const Text('Not assigned to any school yet.');
        }
        return Column(
          children: <Widget>[
            for (final AssessmentAssignment assignment in assignments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.school_outlined),
                title: Text('Grade ${assignment.grade} · '
                    '${assignment.sections.join(', ')}'),
                subtitle: Text(
                  '${assignment.expectedStudentCount} students expected · '
                  '${assignment.status.displayName}',
                ),
              ),
          ],
        );
      },
    );
  }
}

final class _AddAssignmentDialog extends StatefulWidget {
  const _AddAssignmentDialog({required this.assessment, required this.onSubmit});

  final Assessment assessment;
  final Future<Failure?> Function(
    String schoolId,
    List<String> sections,
    int expectedCount,
  )
  onSubmit;

  @override
  State<_AddAssignmentDialog> createState() => _AddAssignmentDialogState();
}

class _AddAssignmentDialogState extends State<_AddAssignmentDialog> {
  final TextEditingController _schoolIdController = TextEditingController();
  final TextEditingController _sectionsController = TextEditingController(
    text: 'A',
  );
  final TextEditingController _countController = TextEditingController(
    text: '40',
  );
  bool _isSubmitting = false;
  Failure? _failure;

  @override
  void dispose() {
    _schoolIdController.dispose();
    _sectionsController.dispose();
    _countController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_schoolIdController.text.trim().isEmpty) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _failure = null;
    });
    final Failure? failure = await widget.onSubmit(
      _schoolIdController.text.trim(),
      _sectionsController.text
          .split(',')
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList(growable: false),
      int.tryParse(_countController.text.trim()) ?? 0,
    );
    if (!mounted) {
      return;
    }
    if (failure != null) {
      setState(() {
        _isSubmitting = false;
        _failure = failure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Assign to a school'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_failure != null) ...<Widget>[
            Text(
              _failure!.userMessage,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _schoolIdController,
            enabled: !_isSubmitting,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'School id',
              helperText: 'Open the school in Schools to copy its id',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sectionsController,
            enabled: !_isSubmitting,
            decoration: const InputDecoration(
              labelText: 'Sections',
              helperText: 'Comma-separated, e.g. A, B',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _countController,
            enabled: !_isSubmitting,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Expected students'),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _isSubmitting ? null : _submit,
        child: _isSubmitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Assign'),
      ),
    ],
  );
}
