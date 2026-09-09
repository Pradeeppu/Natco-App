/// One student's result, question by question.
///
/// The question-by-question table keeps the machine reading and the final
/// answer in separate columns, so a corrected answer is visible as a
/// correction rather than presented as what the machine saw (Critical
/// Rule 3).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/app/theme.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/presentation/controller/assessment_controllers.dart';
import 'package:natco_app/features/auth/domain/entity/permission.dart';
import 'package:natco_app/features/auth/presentation/controller/session_state.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/results/domain/entity/assessment_result.dart';
import 'package:natco_app/features/results/presentation/controller/result_controllers.dart';
import 'package:natco_app/features/students/domain/entity/student.dart';
import 'package:natco_app/features/students/presentation/controller/student_list_controller.dart';

final class StudentResultScreen extends ConsumerWidget {
  const StudentResultScreen({required this.studentId, super.key});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? assessmentId = GoRouterState.of(
      context,
    ).uri.queryParameters['assessmentId'];

    if (assessmentId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Result')),
        body: const SafeArea(
          child: EmptyView(
            title: 'No assessment selected',
            message: 'Open this result from the Results list.',
            icon: Icons.grading_outlined,
          ),
        ),
      );
    }

    final AsyncValue<AssessmentResult?> resultValue = ref.watch(
      resultForStudentProvider((assessmentId: assessmentId, studentId: studentId)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: SafeArea(
        child: resultValue.when(
          loading: () => const LoadingView(),
          error: (Object error, StackTrace _) => FailureView(
            failure: asFailure(error),
            onRetry: () => ref.invalidate(
              resultForStudentProvider((
                assessmentId: assessmentId,
                studentId: studentId,
              )),
            ),
          ),
          data: (AssessmentResult? result) {
            if (result == null) {
              return const EmptyView(
                title: 'Not scored yet',
                message:
                    'This sheet has not finished processing, or is still '
                    'waiting on a validation decision.',
                icon: Icons.hourglass_empty,
              );
            }
            return _ResultBody(result: result);
          },
        ),
      ),
    );
  }
}

final class _ResultBody extends ConsumerWidget {
  const _ResultBody({required this.result});

  final AssessmentResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;
    final SessionState session = ref.watch(sessionProvider);
    final bool canSeeImage = session.authorization.can(Permission.viewOmrImage);
    final AsyncValue<Student> studentValue = ref.watch(
      studentProvider(result.studentId),
    );
    final AsyncValue<Assessment> assessmentValue = ref.watch(
      assessmentProvider(result.assessmentId),
    );
    final AsyncValue<List<OmrAnswer>> answersValue = ref.watch(
      resultAnswersProvider(result.omrId),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Text(
          studentValue.maybeWhen(
            data: (Student s) => s.studentName,
            orElse: () => 'Loading...',
          ),
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 2),
        Text(
          'Grade ${result.grade} - Section ${result.section}\n'
          '${assessmentValue.maybeWhen(
            data: (Assessment a) => '${a.assessmentName} · ${a.subject}',
            orElse: () => '',
          )} · answer key v${result.answerKeyVersion}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            _Metric(
              label: 'Marks',
              value:
                  '${result.marksObtained.toStringAsFixed(0)}/'
                  '${result.totalMarks.toStringAsFixed(0)}',
              color: status.success,
            ),
            _Metric(label: 'Percentage', value: '${result.percentage.round()}%'),
            _Metric(
              label: 'Correct',
              value: '${result.correctCount}',
              color: status.success,
            ),
            _Metric(
              label: 'Incorrect',
              value: '${result.incorrectCount}',
              color: status.danger,
            ),
            _Metric(label: 'Blank', value: '${result.blankCount}'),
          ],
        ),
        const SizedBox(height: 24),
        Text('Question by question', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Machine reading and final answer kept apart',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        answersValue.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (Object error, StackTrace _) =>
              FailureView(failure: asFailure(error)),
          data: (List<OmrAnswer> answers) => _AnswerTable(answers: answers),
        ),
        const SizedBox(height: 20),
        if (canSeeImage)
          OutlinedButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Viewing the original sheet arrives with OMR capture.',
                ),
              ),
            ),
            icon: const Icon(Icons.image_outlined),
            label: const Text('View original OMR sheet'),
          )
        else
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Original sheet not available to your role'),
              subtitle: Text(
                'Viewing captured images requires the viewOmrImage permission.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
  }
}

final class _AnswerTable extends StatelessWidget {
  const _AnswerTable({required this.answers});

  final List<OmrAnswer> answers;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NatcoStatusColors status = theme.statusColors;
    final List<OmrAnswer> sorted = List<OmrAnswer>.of(answers)
      ..sort((a, b) => a.questionNumber.compareTo(b.questionNumber));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Container(
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 44,
                  child: Text('Q', style: theme.textTheme.labelSmall),
                ),
                Expanded(
                  child: Text('Machine', style: theme.textTheme.labelSmall),
                ),
                Expanded(
                  child: Text('Final', style: theme.textTheme.labelSmall),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    'Marks',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
          ...sorted.map(
            (OmrAnswer a) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 44,
                    child: Text('${a.questionNumber}',
                        style: theme.textTheme.bodyMedium),
                  ),
                  Expanded(
                    child: Text(
                      a.machineAnswer ?? '—',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        Text(
                          a.finalAnswer ?? '—',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (a.isValidated) ...<Widget>[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.how_to_reg_outlined,
                            size: 15,
                            color: status.warning,
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        Icon(
                          a.isCorrect == true
                              ? Icons.check_circle
                              : Icons.cancel,
                          size: 16,
                          color: a.isCorrect == true
                              ? status.success
                              : status.danger,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          (a.marks ?? 0).toStringAsFixed(0),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
            style: theme.textTheme.titleMedium?.copyWith(color: color),
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
