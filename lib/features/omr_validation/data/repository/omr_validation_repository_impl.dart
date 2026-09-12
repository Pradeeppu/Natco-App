/// The single [OmrValidationRepository] implementation.
///
/// Composes a swappable [OmrValidationDataSource] with [OmrValidationPolicy]
/// and audit logging — written once here rather than per backend, mirroring
/// `StudentRepositoryImpl`.
library;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/services/file_system_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/omr_processing/domain/entity/image_quality_report.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_template.dart';
import 'package:natco_app/features/omr_processing/domain/service/omr_processor.dart';
import 'package:natco_app/features/omr_validation/data/service/omr_validation_data_source.dart';
import 'package:natco_app/features/omr_validation/domain/entity/omr_validation_record.dart';
import 'package:natco_app/features/omr_validation/domain/repository/omr_validation_repository.dart';
import 'package:natco_app/features/omr_validation/domain/service/omr_validation_policy.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';
import 'package:natco_app/features/sync/domain/entity/sync_status.dart';
import 'package:natco_app/features/sync/domain/repository/sync_queue_repository.dart';

final class OmrValidationRepositoryImpl implements OmrValidationRepository {
  OmrValidationRepositoryImpl({
    required OmrValidationDataSource dataSource,
    required AuditSink auditSink,
    required IdGenerator idGenerator,
    required Clock clock,
    required DeviceInfoService deviceInfo,
    required SyncQueueRepository syncQueue,
    required FileSystemService fileSystem,
  }) : _dataSource = dataSource,
       _auditSink = auditSink,
       _idGenerator = idGenerator,
       _clock = clock,
       _deviceInfo = deviceInfo,
       _syncQueue = syncQueue,
       _fileSystem = fileSystem;

  final OmrValidationDataSource _dataSource;
  final AuditSink _auditSink;
  final IdGenerator _idGenerator;
  final Clock _clock;
  final DeviceInfoService _deviceInfo;
  final SyncQueueRepository _syncQueue;
  final FileSystemService _fileSystem;

  @override
  Future<Result<Page<OmrSubmission>>> listQueue({
    required AccessScope scope,
    String query = '',
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) => _dataSource.listQueue(
    scope: scope,
    query: query,
    cursor: cursor,
    pageSize: pageSize,
  );

  @override
  Future<Result<OmrSubmission>> getSubmission(String omrId) =>
      _dataSource.getSubmission(omrId);

  @override
  Future<Result<Page<OmrSubmission>>> listSubmissionsForAssessment({
    required String assessmentId,
    required AccessScope scope,
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) => _dataSource.listSubmissionsForAssessment(
    assessmentId: assessmentId,
    scope: scope,
    cursor: cursor,
    pageSize: pageSize,
  );

  @override
  Future<Result<List<OmrAnswer>>> getAnswers(String omrId) =>
      _dataSource.getAnswers(omrId);

  @override
  Future<Result<List<OmrValidationRecord>>> getValidationHistory(
    String omrId,
  ) => _dataSource.getValidationHistory(omrId);

  @override
  Future<Result<OmrAnswer>> recordDecision({
    required String omrId,
    required int questionNumber,
    required String chosenAnswer,
    String? reason,
    required String actorUserId,
    required String actorRole,
  }) async {
    final Failure? choiceDenial = OmrValidationPolicy.checkChoice(chosenAnswer);
    if (choiceDenial != null) {
      return err(choiceDenial);
    }

    final Result<List<OmrAnswer>> answersResult = await _dataSource.getAnswers(
      omrId,
    );
    if (answersResult.isFailure) {
      return err(answersResult.failureOrNull!);
    }
    final List<OmrAnswer> answers = answersResult.valueOrNull!;
    final int index = answers.indexWhere(
      (OmrAnswer a) => a.questionNumber == questionNumber,
    );
    if (index < 0) {
      return err(
        NotFoundFailure(
          userMessage: 'That question could not be found on this sheet.',
          entityType: 'omr_answer',
          entityId: '$omrId#q$questionNumber',
        ),
      );
    }
    final OmrAnswer current = answers[index];
    final Failure? belongsDenial = OmrValidationPolicy.checkAnswerBelongsToSubmission(
      answer: current,
      omrId: omrId,
    );
    if (belongsDenial != null) {
      return err(belongsDenial);
    }

    final DateTime now = _clock.nowUtc();
    // The only way `finalAnswer`/`finalAnswerSource`/`validatedBy`/
    // `validatedAt`/`validationReason` change — every machine-evidence field
    // is carried forward untouched by construction (Critical Rule 3).
    final OmrAnswer updated = current.withValidation(
      finalAnswer: chosenAnswer,
      validatedBy: actorUserId,
      validatedAt: now,
      validationReason: reason,
    );

    final Result<OmrAnswer> saveResult = await _dataSource.saveAnswer(updated);
    if (saveResult.isFailure) {
      return err(saveResult.failureOrNull!);
    }

    await _syncQueue.enqueue(
      SyncQueueEntry(
        syncId: _idGenerator.newId(),
        entityType: SyncEntityType.omrAnswer,
        entityId: '$omrId#q$questionNumber',
        operation: SyncOperation.update,
        payloadRef: 'local/omr_answers/$omrId#q$questionNumber',
        idempotencyKey: 'update_answer_${omrId}_q$questionNumber',
        createdAt: now,
        attemptCount: 0,
        status: SyncStatus.pending,
      ),
    );

    final String validationId = _idGenerator.newId();
    await _dataSource.appendValidationRecord(
      OmrValidationRecord(
        validationId: validationId,
        omrId: omrId,
        questionNumber: questionNumber,
        machineAnswer: current.machineAnswer,
        machineConfidence: current.machineConfidence,
        chosenAnswer: chosenAnswer,
        validatorUserId: actorUserId,
        validatedAt: now,
        deviceId: _deviceInfo.deviceId,
        reason: reason,
      ),
    );

    await _syncQueue.enqueue(
      SyncQueueEntry(
        syncId: _idGenerator.newId(),
        entityType: SyncEntityType.omrValidation,
        entityId: validationId,
        operation: SyncOperation.create,
        payloadRef: 'local/omr_validations/$validationId',
        idempotencyKey: 'create_validation_$validationId',
        createdAt: now,
        attemptCount: 0,
        status: SyncStatus.pending,
      ),
    );

    await _auditSink.record(
      AuditEvent(
        auditId: _idGenerator.newId(),
        userId: actorUserId,
        role: actorRole,
        action: AuditAction.omrValidated,
        entityType: 'omr_answer',
        entityId: '$omrId#q$questionNumber',
        timestamp: now,
        deviceId: _deviceInfo.deviceId,
        appVersion: _deviceInfo.appVersion,
        oldValue: <String, Object?>{
          'machineAnswer': current.machineAnswer,
          'machineStatus': current.machineStatus.wireName,
        },
        newValue: <String, Object?>{'finalAnswer': chosenAnswer},
      ),
    );

    // Refresh so the completeness check runs against the answer this method
    // just wrote, not the pre-write snapshot — a batch of validations moving
    // one submission to COMPLETED must be exactly the write that resolves the
    // *last* flagged question, not one that races ahead of it.
    final List<OmrAnswer> refreshed = List<OmrAnswer>.of(answers)
      ..[index] = updated;
    if (OmrValidationPolicy.isFullyValidated(refreshed)) {
      final Result<OmrSubmission> submissionResult = await _dataSource
          .getSubmission(omrId);
      if (submissionResult.isSuccess) {
        final OmrSubmission submission = submissionResult.valueOrNull!;
        if (submission.needsValidation) {
          await _dataSource.saveSubmission(
            submission.copyWith(
              validationStatus: ValidationStatus.completed,
              updatedAt: now,
            ),
          );
        }
      }
    }

    return ok(updated);
  }

  @override
  Future<Result<void>> applyScoredAnswers(
    List<OmrAnswer> scoredAnswers,
  ) async {
    for (final OmrAnswer answer in scoredAnswers) {
      final Result<OmrAnswer> result = await _dataSource.saveAnswer(answer);
      if (result.isFailure) {
        return err(result.failureOrNull!);
      }
    }
    return ok(null);
  }

  @override
  Future<Result<OmrSubmission>> markScored(
    String omrId, {
    required int answerKeyVersion,
    required double machineScore,
    required double finalScore,
  }) async {
    final Result<OmrSubmission> current = await _dataSource.getSubmission(
      omrId,
    );
    if (current.isFailure) {
      return err(current.failureOrNull!);
    }
    return _dataSource.saveSubmission(
      current.valueOrNull!.copyWith(
        processingStatus: OmrProcessingStatus.scored,
        answerKeyVersion: answerKeyVersion,
        machineScore: machineScore,
        finalScore: finalScore,
        updatedAt: _clock.nowUtc(),
      ),
    );
  }

  @override
  Future<Result<List<OmrSubmission>>> listCapturedOrProcessing() =>
      _dataSource.listCapturedOrProcessing();

  @override
  Future<Result<OmrSubmission>> markEvidenceMissing(String omrId) async {
    final Result<OmrSubmission> current = await _dataSource.getSubmission(
      omrId,
    );
    if (current.isFailure) {
      return err(current.failureOrNull!);
    }
    final Result<OmrSubmission> result = await _dataSource.saveSubmission(
      current.valueOrNull!.copyWith(
        processingStatus: OmrProcessingStatus.unreadableEvidenceMissing,
        updatedAt: _clock.nowUtc(),
      ),
    );
    if (result.isSuccess) {
      // Recorded rather than silently dropped — the whole point of this
      // status (docs/06-offline-sync-strategy.md §4, step 4). A Supervisor
      // finds it through `reviewExceptions`, not by noticing a sheet is
      // simply gone.
      await _auditSink.record(
        AuditEvent(
          auditId: _idGenerator.newId(),
          userId: 'SYSTEM',
          role: 'SYSTEM',
          action: AuditAction.omrEvidenceMissing,
          entityType: 'omr_submission',
          entityId: omrId,
          timestamp: _clock.nowUtc(),
          deviceId: _deviceInfo.deviceId,
          appVersion: _deviceInfo.appVersion,
        ),
      );
      
      await _syncQueue.enqueue(
        SyncQueueEntry(
          syncId: _idGenerator.newId(),
          entityType: SyncEntityType.omrSubmission,
          entityId: omrId,
          operation: SyncOperation.update,
          payloadRef: 'local/omr_submissions/$omrId',
          idempotencyKey: 'update_submission_$omrId',
          createdAt: _clock.nowUtc(),
          attemptCount: 0,
          status: SyncStatus.pending,
        ),
      );
    }
    return result;
  }

  @override
  Future<Result<OmrSubmission>> resetToCaptured(String omrId) async {
    final Result<OmrSubmission> current = await _dataSource.getSubmission(
      omrId,
    );
    if (current.isFailure) {
      return err(current.failureOrNull!);
    }
    final OmrSubmission submission = current.valueOrNull!;
    if (submission.processingStatus != OmrProcessingStatus.processing) {
      // Nothing to reset — resetting a submission that is not actually stuck
      // would be an unasked-for state change, not a recovery.
      return ok(submission);
    }
    final Result<OmrSubmission> result = await _dataSource.saveSubmission(
      submission.copyWith(
        processingStatus: OmrProcessingStatus.captured,
        updatedAt: _clock.nowUtc(),
      ),
    );
    if (result.isSuccess) {
      await _syncQueue.enqueue(
        SyncQueueEntry(
          syncId: _idGenerator.newId(),
          entityType: SyncEntityType.omrSubmission,
          entityId: omrId,
          operation: SyncOperation.update,
          payloadRef: 'local/omr_submissions/$omrId',
          idempotencyKey: 'update_submission_$omrId',
          createdAt: _clock.nowUtc(),
          attemptCount: 0,
          status: SyncStatus.pending,
        ),
      );
    }
    return result;
  }

  @override
  Future<Result<OmrSubmission>> createSubmission({
    required String omrId,
    required String sessionId,
    required String assessmentId,
    String? studentId,
    required String schoolId,
    required String clusterId,
    required String districtId,
    required String stateId,
    required String capturedBy,
    required String actorRole,
    required String originalImagePath,
    required ImageQualityReport imageQuality,
    String? qualityOverrideBy,
    String? qualityOverrideReason,
  }) async {
    final DateTime now = _clock.nowUtc();
    final OmrSubmission submission = OmrSubmission(
      omrId: omrId,
      submissionId: _idGenerator.newId(),
      sessionId: sessionId,
      assessmentId: assessmentId,
      studentId: studentId,
      schoolId: schoolId,
      clusterId: clusterId,
      districtId: districtId,
      stateId: stateId,
      capturedBy: capturedBy,
      capturedAt: now,
      deviceId: _deviceInfo.deviceId,
      originalImagePath: originalImagePath,
      imageQuality: imageQuality,
      qualityOverrideBy: qualityOverrideBy,
      qualityOverrideReason: qualityOverrideReason,
      // Phase 6's pipeline is what moves this forward; a fresh capture always
      // starts here regardless of the quality verdict — even an overridden
      // failure still needs processing run against it.
      processingStatus: OmrProcessingStatus.captured,
      validationStatus: ValidationStatus.notRequired,
      createdAt: now,
      updatedAt: now,
    );

    final Result<OmrSubmission> result = await _dataSource.createSubmission(
      submission,
    );
    if (result.isFailure) {
      return result;
    }

    await _syncQueue.enqueue(
      SyncQueueEntry(
        syncId: _idGenerator.newId(),
        entityType: SyncEntityType.omrSubmission,
        entityId: omrId,
        operation: SyncOperation.create,
        payloadRef: 'local/omr_submissions/$omrId',
        idempotencyKey: 'create_submission_$omrId',
        createdAt: now,
        attemptCount: 0,
        status: SyncStatus.pending,
      ),
    );

    await _auditSink.record(
      AuditEvent(
        auditId: _idGenerator.newId(),
        userId: capturedBy,
        role: actorRole,
        action: AuditAction.omrCaptured,
        entityType: 'omr_submission',
        entityId: omrId,
        timestamp: now,
        deviceId: _deviceInfo.deviceId,
        appVersion: _deviceInfo.appVersion,
        // Quality verdict only — never studentId (Critical Rule 11: no
        // student identifier in an audit entry).
        newValue: <String, Object?>{
          'assessmentId': assessmentId,
          'qualityVerdict': imageQuality.verdict.wireName,
        },
      ),
    );

    if (qualityOverrideBy != null) {
      await _auditSink.record(
        AuditEvent(
          auditId: _idGenerator.newId(),
          userId: qualityOverrideBy,
          role: actorRole,
          action: AuditAction.omrQualityOverridden,
          entityType: 'omr_submission',
          entityId: omrId,
          timestamp: now,
          deviceId: _deviceInfo.deviceId,
          appVersion: _deviceInfo.appVersion,
          newValue: <String, Object?>{
            'qualityVerdict': imageQuality.verdict.wireName,
            'reason': qualityOverrideReason,
          },
        ),
      );
    }

    return result;
  }

  @override
  Future<Result<OmrSubmission>> processSubmission(
    String omrId, {
    required OmrTemplate template,
    required int questionCount,
  }) async {
    final Result<OmrSubmission> current = await _dataSource.getSubmission(omrId);
    if (current.isFailure) {
      return err(current.failureOrNull!);
    }
    final OmrSubmission submission = current.valueOrNull!;

    if (submission.processingStatus != OmrProcessingStatus.captured) {
      return ok(submission);
    }

    final DateTime now = _clock.nowUtc();
    final OmrSubmission processing = submission.copyWith(
      processingStatus: OmrProcessingStatus.processing,
      updatedAt: now,
    );
    final Result<OmrSubmission> processingUpdate = await _dataSource.saveSubmission(processing);
    if (processingUpdate.isFailure) {
      return err(processingUpdate.failureOrNull!);
    }

    Uint8List? bytes;
    try {
      bytes = await _fileSystem.readBytes(processing.originalImagePath);
    } catch (_) {
      return markEvidenceMissing(omrId);
    }

    final OmrProcessingResult result = await compute(
      _runProcessor,
      _OmrProcessorPayload(
        imageBytes: bytes,
        template: template,
        questionCount: questionCount,
      ),
    );

    if (!result.sheetAligned || !result.omrIdReadable) {
      return resetToCaptured(omrId);
    }

    bool needsValidation = false;
    for (final OmrQuestionReading q in result.questions) {
      final OmrAnswer answer = OmrAnswer(
        omrAnswerId: _idGenerator.newId(),
        omrId: omrId,
        questionNumber: q.questionNumber,
        optionScores: q.optionScores,
        machineAnswer: q.machineAnswer,
        machineConfidence: q.machineConfidence,
        machineStatus: q.machineStatus,
        finalAnswer: q.machineAnswer,
        finalAnswerSource: AnswerSource.machine,
      );
      if (answer.needsValidation) {
        needsValidation = true;
      }
      final Result<OmrAnswer> answerSaved = await _dataSource.saveAnswer(answer);
      if (answerSaved.isFailure) return err(answerSaved.failureOrNull!);
      
      await _syncQueue.enqueue(
        SyncQueueEntry(
          syncId: _idGenerator.newId(),
          entityType: SyncEntityType.omrAnswer,
          entityId: '$omrId#q${q.questionNumber}',
          operation: SyncOperation.update,
          payloadRef: 'local/omr_answers/$omrId#q${q.questionNumber}',
          idempotencyKey: 'update_answer_${omrId}_q${q.questionNumber}',
          createdAt: _clock.nowUtc(),
          attemptCount: 0,
          status: SyncStatus.pending,
        ),
      );
    }

    final OmrSubmission finished = processing.copyWith(
      processingStatus: needsValidation 
          ? OmrProcessingStatus.needsValidation 
          : OmrProcessingStatus.processed,
      validationStatus: needsValidation 
          ? ValidationStatus.pending 
          : ValidationStatus.notRequired,
      updatedAt: _clock.nowUtc(),
    );

    final Result<OmrSubmission> finalSave = await _dataSource.saveSubmission(finished);
    if (finalSave.isFailure) return err(finalSave.failureOrNull!);

    await _syncQueue.enqueue(
      SyncQueueEntry(
        syncId: _idGenerator.newId(),
        entityType: SyncEntityType.omrSubmission,
        entityId: omrId,
        operation: SyncOperation.update,
        payloadRef: 'local/omr_submissions/$omrId',
        idempotencyKey: 'update_submission_$omrId',
        createdAt: _clock.nowUtc(),
        attemptCount: 0,
        status: SyncStatus.pending,
      ),
    );

    return ok(finished);
  }
}

final class _OmrProcessorPayload {
  const _OmrProcessorPayload({
    required this.imageBytes,
    required this.template,
    required this.questionCount,
  });
  final Uint8List imageBytes;
  final OmrTemplate template;
  final int questionCount;
}

OmrProcessingResult _runProcessor(_OmrProcessorPayload payload) {
  final img.Image? decoded = img.decodeImage(payload.imageBytes);
  if (decoded == null) {
    return const OmrProcessingResult.alignmentFailed(
      markersFound: 0,
      reason: 'Could not decode image file.',
    );
  }
  return OmrProcessor.process(
    image: decoded,
    template: payload.template,
    questionCount: payload.questionCount,
  );
}
