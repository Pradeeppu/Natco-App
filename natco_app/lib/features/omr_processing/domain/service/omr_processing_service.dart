/// Orchestrates one submission through the whole engine: read the durable
/// image, run the pipeline in a worker isolate, persist the resulting
/// answers, and drive `OmrSubmission.processingStatus` through the state
/// machine — the glue between `OmrProcessingPipeline` (a pure function) and
/// the repositories a real submission actually lives in.
library;

import 'dart:typed_data';

import 'package:natco_app/app/config/scanner_thresholds.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/omr_capture/data/service/omr_image_store.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_processing_status.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_capture/domain/entity/validation_status.dart';
import 'package:natco_app/features/omr_capture/domain/repository/omr_submissions_repository.dart';
import 'package:natco_app/features/omr_processing/data/service/omr_pipeline_runner.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_processing_outcome.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/entity/question_detection_result.dart';
import 'package:natco_app/features/omr_processing/domain/repository/omr_answers_repository.dart';

final class OmrProcessingService {
  OmrProcessingService({
    required OmrSubmissionsRepository submissions,
    required OmrAnswersRepository answers,
    required OmrImageStore imageStore,
    required IdGenerator idGenerator,
    required OmrTemplate template,
    OmrPipelineRunner runner = const IsolateOmrPipelineRunner(),
  }) : _submissions = submissions,
       _answers = answers,
       _imageStore = imageStore,
       _idGenerator = idGenerator,
       _template = template,
       _runner = runner;

  final OmrSubmissionsRepository _submissions;
  final OmrAnswersRepository _answers;
  final OmrImageStore _imageStore;
  final IdGenerator _idGenerator;
  final OmrTemplate _template;
  final OmrPipelineRunner _runner;

  /// Runs the engine for [submissionId] and persists everything it
  /// produces. [questionCount] comes from the assessment this sheet
  /// belongs to — the template can hold more bubbles than any one
  /// assessment actually asks.
  Future<Result<OmrProcessingOutcome>> processSubmission({
    required String submissionId,
    required int questionCount,
    required ScannerThresholds thresholds,
  }) async {
    final Result<OmrSubmission?> loaded = await _submissions.getSubmission(
      submissionId,
    );
    if (loaded.isFailure) {
      return err(loaded.failureOrNull!);
    }
    final OmrSubmission? submission = loaded.valueOrNull;
    if (submission == null) {
      return err(
        NotFoundFailure(
          userMessage: 'That submission could not be found.',
          entityType: 'omr_submission',
          entityId: submissionId,
        ),
      );
    }

    final Result<OmrSubmission> intoProcessing = await _submissions
        .transitionProcessingStatus(
          submissionId,
          to: OmrProcessingStatus.processing,
        );
    if (intoProcessing.isFailure) {
      return err(intoProcessing.failureOrNull!);
    }

    final Result<Uint8List> bytesResult = await _imageStore.read(
      submission.originalImagePath,
    );
    if (bytesResult.isFailure) {
      await _submissions.transitionProcessingStatus(
        submissionId,
        to: OmrProcessingStatus.processingFailed,
      );
      return err(bytesResult.failureOrNull!);
    }

    final Result<OmrProcessingOutcome> pipelineResult = await _runner.run(
      bytesResult.valueOrNull!,
      template: _template,
      questionCount: questionCount,
      thresholds: thresholds,
      imageQualityScore: submission.imageQuality.overallScore,
      qualityWasOverridden: submission.qualityOverride != null,
    );
    if (pipelineResult.isFailure) {
      await _submissions.transitionProcessingStatus(
        submissionId,
        to: OmrProcessingStatus.processingFailed,
      );
      return err(pipelineResult.failureOrNull!);
    }

    final OmrProcessingOutcome outcome = pipelineResult.valueOrNull!;
    final List<OmrAnswer> records = <OmrAnswer>[
      for (final QuestionDetectionResult q in outcome.questionResults)
        OmrAnswer(
          omrAnswerId: _idGenerator.newId(),
          omrId: submission.omrId,
          questionNumber: q.questionNumber,
          optionScores: q.optionScores,
          machineAnswer: q.machineAnswer,
          machineConfidence: q.machineConfidence,
          machineStatus: q.machineStatus,
        ),
    ];
    final Result<List<OmrAnswer>> writeResult = await _answers.createAnswers(
      records,
    );
    if (writeResult.isFailure) {
      return err(writeResult.failureOrNull!);
    }

    final Result<OmrSubmission> intoProcessed = await _submissions
        .transitionProcessingStatus(
          submissionId,
          to: OmrProcessingStatus.processed,
        );
    if (intoProcessed.isFailure) {
      return err(intoProcessed.failureOrNull!);
    }

    final OmrProcessingStatus finalStatus = outcome.needsValidation
        ? OmrProcessingStatus.needsValidation
        : OmrProcessingStatus.readyForScoring;
    final ValidationStatus validationStatus = outcome.needsValidation
        ? ValidationStatus.pending
        : ValidationStatus.notRequired;
    final Result<OmrSubmission> finalTransition = await _submissions
        .transitionProcessingStatus(
          submissionId,
          to: finalStatus,
          validationStatus: validationStatus,
        );
    if (finalTransition.isFailure) {
      return err(finalTransition.failureOrNull!);
    }

    return ok(outcome);
  }
}
