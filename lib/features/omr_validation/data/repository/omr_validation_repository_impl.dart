/// The single [OmrValidationRepository] implementation.
///
/// Composes a swappable [OmrValidationDataSource] with [OmrValidationPolicy]
/// and audit logging — written once here rather than per backend, mirroring
/// `StudentRepositoryImpl`.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/omr_processing/domain/entity/image_quality_report.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_validation/data/service/omr_validation_data_source.dart';
import 'package:natco_app/features/omr_validation/domain/entity/omr_validation_record.dart';
import 'package:natco_app/features/omr_validation/domain/repository/omr_validation_repository.dart';
import 'package:natco_app/features/omr_validation/domain/service/omr_validation_policy.dart';

final class OmrValidationRepositoryImpl implements OmrValidationRepository {
  OmrValidationRepositoryImpl({
    required OmrValidationDataSource dataSource,
    required AuditSink auditSink,
    required IdGenerator idGenerator,
    required Clock clock,
    required DeviceInfoService deviceInfo,
  }) : _dataSource = dataSource,
       _auditSink = auditSink,
       _idGenerator = idGenerator,
       _clock = clock,
       _deviceInfo = deviceInfo;

  final OmrValidationDataSource _dataSource;
  final AuditSink _auditSink;
  final IdGenerator _idGenerator;
  final Clock _clock;
  final DeviceInfoService _deviceInfo;

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

    await _dataSource.appendValidationRecord(
      OmrValidationRecord(
        validationId: _idGenerator.newId(),
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
    return _dataSource.saveSubmission(
      submission.copyWith(
        processingStatus: OmrProcessingStatus.captured,
        updatedAt: _clock.nowUtc(),
      ),
    );
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
}
