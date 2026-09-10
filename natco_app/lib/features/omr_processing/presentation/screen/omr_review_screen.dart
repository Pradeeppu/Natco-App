/// Reviews one captured sheet's engine output: run the detection engine
/// on it, then show the per-question detected answer, confidence and
/// status.
///
/// Deliberately narrower than Phase 1's placeholder for this screen
/// described: no score preview (Phase 8 has not built scoring yet) and no
/// duplicate-registry check (the `omr_registry` this would need does not
/// exist yet either) — both real capabilities this phase does not add,
/// left off rather than shown against invented data.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/widgets/app_state_views.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_processing_status.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_capture/domain/entity/validation_status.dart';
import 'package:natco_app/features/omr_processing/domain/entity/detection_status.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';

final class OmrReviewScreen extends ConsumerStatefulWidget {
  const OmrReviewScreen({required this.omrId, super.key});

  final String omrId;

  @override
  ConsumerState<OmrReviewScreen> createState() => _OmrReviewScreenState();
}

enum _Step { loading, ready, processing, error }

class _OmrReviewScreenState extends ConsumerState<OmrReviewScreen> {
  _Step _step = _Step.loading;
  OmrSubmission? _submission;
  List<OmrAnswer> _answers = const <OmrAnswer>[];
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final submissionResult = await ref
        .read(omrSubmissionsRepositoryProvider)
        .getSubmissionByOmrId(widget.omrId);
    final OmrSubmission? submission = submissionResult.valueOrNull;
    if (!mounted) {
      return;
    }
    if (submission == null) {
      setState(() {
        _step = _Step.error;
        _failure =
            submissionResult.failureOrNull ??
            NotFoundFailure(
              userMessage: 'That sheet could not be found.',
              entityType: 'omr_submission',
              entityId: widget.omrId,
            );
      });
      return;
    }
    final answersResult = await ref
        .read(omrAnswersRepositoryProvider)
        .listForOmrId(widget.omrId);
    if (!mounted) {
      return;
    }
    setState(() {
      _submission = submission;
      _answers = answersResult.valueOrNull ?? const <OmrAnswer>[];
      _failure = null;
      _step = _Step.ready;
    });
  }

  Future<void> _process() async {
    final OmrSubmission submission = _submission!;
    setState(() => _step = _Step.processing);

    final questionsResult = await ref
        .read(assessmentsRepositoryProvider)
        .listQuestions(submission.assessmentId);
    final int questionCount = questionsResult.valueOrNull?.length ?? 0;

    final service = await ref.read(omrProcessingServiceProvider.future);
    final result = await service.processSubmission(
      submissionId: submission.submissionId,
      questionCount: questionCount,
      thresholds: ref.read(appConfigProvider).scannerThresholds,
    );
    if (!mounted) {
      return;
    }
    if (result.isFailure) {
      setState(() => _failure = result.failureOrNull);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Sheet ${widget.omrId}')),
    body: SafeArea(
      child: switch (_step) {
        _Step.loading => const LoadingView(),
        _Step.processing => const LoadingView(message: 'Reading the sheet…'),
        _Step.error => FailureView(
          failure: _failure ?? const UnexpectedFailure(),
          onRetry: _load,
        ),
        _Step.ready => _ReadyBody(
          submission: _submission!,
          answers: _answers,
          failure: _failure,
          onProcess: _process,
        ),
      },
    ),
  );
}

final class _ReadyBody extends StatelessWidget {
  const _ReadyBody({
    required this.submission,
    required this.answers,
    required this.failure,
    required this.onProcess,
  });

  final OmrSubmission submission;
  final List<OmrAnswer> answers;
  final Failure? failure;
  final VoidCallback onProcess;

  bool get _canProcess =>
      submission.processingStatus == OmrProcessingStatus.qualityChecked ||
      submission.processingStatus == OmrProcessingStatus.processingFailed;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: <Widget>[
      if (failure != null) ...<Widget>[
        InfoBanner(message: failure!.userMessage, icon: Icons.error_outline, isWarning: true),
        const SizedBox(height: 16),
      ],
      _StatusCard(submission: submission),
      const SizedBox(height: 16),
      if (_canProcess)
        FilledButton.icon(
          onPressed: onProcess,
          icon: const Icon(Icons.document_scanner_outlined),
          label: Text(
            submission.processingStatus == OmrProcessingStatus.processingFailed
                ? 'Retry processing'
                : 'Process this sheet',
          ),
        ),
      if (answers.isNotEmpty) ...<Widget>[
        const SizedBox(height: 24),
        Text('Detected answers', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final OmrAnswer answer in answers) _AnswerRow(answer: answer),
      ],
    ],
  );
}

final class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.submission});

  final OmrSubmission submission;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Processing status', style: Theme.of(context).textTheme.labelMedium),
          Text(submission.processingStatus.wireName),
          if (submission.processingStatus == OmrProcessingStatus.needsValidation ||
              submission.validationStatus != ValidationStatus.notRequired) ...<Widget>[
            const SizedBox(height: 8),
            Text('Validation status', style: Theme.of(context).textTheme.labelMedium),
            Text(submission.validationStatus.wireName),
          ],
        ],
      ),
    ),
  );
}

final class _AnswerRow extends StatelessWidget {
  const _AnswerRow({required this.answer});

  final OmrAnswer answer;

  Color _statusColor(BuildContext context) => switch (answer.machineStatus) {
    DetectionStatus.highConfidence => Colors.green,
    DetectionStatus.mediumConfidence => Colors.orange,
    DetectionStatus.lowConfidence ||
    DetectionStatus.multipleMark ||
    DetectionStatus.unreadable => Theme.of(context).colorScheme.error,
    DetectionStatus.blank => Colors.grey,
  };

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      radius: 14,
      backgroundColor: _statusColor(context),
      child: Text(
        '${answer.questionNumber}',
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
    ),
    title: Text(answer.machineAnswer ?? answer.machineStatus.wireName),
    subtitle: Text(
      '${answer.machineStatus.wireName} · '
      'confidence ${(answer.machineConfidence * 100).round()}%',
    ),
  );
}
