/// Versioned answer keys: publish the first version, or correct the
/// published one into the next (docs/02-data-model.md Critical Rules 5-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key_status.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/presentation/controller/assessment_detail_provider.dart';
import 'package:natco_app/features/assessments/presentation/widget/answer_key_entry_dialog.dart';

final class AnswerKeyScreen extends ConsumerWidget {
  const AnswerKeyScreen({required this.assessmentId, super.key});

  final String assessmentId;

  Future<void> _openEntryDialog(
    BuildContext context,
    WidgetRef ref,
    Assessment assessment,
    AnswerKey? published,
  ) async {
    await showAnswerKeyEntryDialog(
      context: context,
      questionCount: assessment.questionCount,
      options: assessment.options,
      existingAnswers: published?.answers ?? const <int, String>{},
      isCorrection: published != null,
      onSubmit: (Map<int, String> answers, String? changeReason) async {
        final result = await ref
            .read(assessmentsRepositoryProvider)
            .publishAnswerKey(
              assessmentId: assessmentId,
              answers: answers,
              changeReason: changeReason,
            );
        return result.failureOrNull;
      },
    );
    ref
      ..invalidate(answerKeyVersionsProvider(assessmentId))
      ..invalidate(assessmentDetailProvider(assessmentId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Assessment?> assessmentAsync = ref.watch(
      assessmentDetailProvider(assessmentId),
    );
    final AsyncValue<List<AnswerKey>> versionsAsync = ref.watch(
      answerKeyVersionsProvider(assessmentId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Answer key')),
      body: SafeArea(
        child: assessmentAsync.when(
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
                icon: Icons.key_outlined,
              );
            }
            return versionsAsync.when(
              loading: () => const LoadingView(),
              error: (Object error, StackTrace stackTrace) => FailureView(
                failure: error is AssessmentDetailFailure
                    ? error.failure
                    : const UnexpectedFailure(),
                onRetry: () => ref.invalidate(answerKeyVersionsProvider(assessmentId)),
              ),
              data: (List<AnswerKey> versions) {
                final AnswerKey? published = versions
                    .cast<AnswerKey?>()
                    .firstWhere(
                      (AnswerKey? k) => k?.status == AnswerKeyStatus.published,
                      orElse: () => null,
                    );
                return _AnswerKeyBody(
                  assessment: assessment,
                  versions: versions,
                  published: published,
                  onPublish: () => _openEntryDialog(
                    context,
                    ref,
                    assessment,
                    published,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

final class _AnswerKeyBody extends StatelessWidget {
  const _AnswerKeyBody({
    required this.assessment,
    required this.versions,
    required this.published,
    required this.onPublish,
  });

  final Assessment assessment;
  final List<AnswerKey> versions;
  final AnswerKey? published;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Newest first: what changed most recently is what a reviewer cares
    // about first.
    final List<AnswerKey> newestFirst = versions.reversed.toList(
      growable: false,
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(assessment.assessmentName, style: theme.textTheme.titleLarge),
        Text(
          '${assessment.questionCount} questions · options: '
          '${assessment.options.join(', ')}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onPublish,
          icon: Icon(published == null ? Icons.publish_outlined : Icons.edit_outlined),
          label: Text(published == null ? 'Publish answer key' : 'Correct answer key'),
        ),
        const SizedBox(height: 24),
        Text('Version history', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (newestFirst.isEmpty)
          const Text('No version has been published yet.')
        else
          for (final AnswerKey version in newestFirst) _VersionCard(version: version),
      ],
    );
  }
}

final class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.version});

  final AnswerKey version;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isPublished = version.status == AnswerKeyStatus.published;
    final String answersText = <String>[
      for (int n = 1; n <= version.answers.length; n++) version.answers[n] ?? '?',
    ].join(', ');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  'Version ${version.version}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    isPublished ? 'Published' : 'Superseded',
                  ),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: isPublished
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Answers: $answersText', style: theme.textTheme.bodyMedium),
            if (version.changeReason != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'Reason: ${version.changeReason}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
