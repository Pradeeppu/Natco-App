/// The single [ResultRepository] implementation.
///
/// Composes a swappable [ResultDataSource] with [ScoringEngine] and every
/// upstream repository scoring needs to read — the session (for the
/// grade/section/key-version a sitting was pinned to), the assessment and its
/// published key (for marks and negative marking), and the OMR validation
/// repository (for the submission and its answers, and for the two narrow
/// writes scoring makes back onto them). Audit logging is written once here,
/// mirroring `StudentRepositoryImpl`.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessment_sessions/domain/entity/assessment_session.dart';
import 'package:natco_app/features/assessment_sessions/domain/repository/session_repository.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/repository/assessment_repository.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_answer.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_validation/domain/repository/omr_validation_repository.dart';
import 'package:natco_app/features/omr_validation/domain/service/omr_validation_policy.dart';
import 'package:natco_app/features/results/data/service/result_data_source.dart';
import 'package:natco_app/features/results/domain/entity/assessment_result.dart';
import 'package:natco_app/features/results/domain/repository/result_repository.dart';
import 'package:natco_app/features/results/domain/service/scoring_engine.dart';

final class ResultRepositoryImpl implements ResultRepository {
  ResultRepositoryImpl({
    required ResultDataSource dataSource,
    required OmrValidationRepository omrRepository,
    required SessionRepository sessionRepository,
    required AssessmentRepository assessmentRepository,
    required AuditSink auditSink,
    required IdGenerator idGenerator,
    required Clock clock,
    required DeviceInfoService deviceInfo,
  }) : _dataSource = dataSource,
       _omrRepository = omrRepository,
       _sessionRepository = sessionRepository,
       _assessmentRepository = assessmentRepository,
       _auditSink = auditSink,
       _idGenerator = idGenerator,
       _clock = clock,
       _deviceInfo = deviceInfo;

  final ResultDataSource _dataSource;
  final OmrValidationRepository _omrRepository;
  final SessionRepository _sessionRepository;
  final AssessmentRepository _assessmentRepository;
  final AuditSink _auditSink;
  final IdGenerator _idGenerator;
  final Clock _clock;
  final DeviceInfoService _deviceInfo;

  @override
  Future<Result<Page<AssessmentResult>>> listResults({
    required String assessmentId,
    required AccessScope scope,
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) => _dataSource.listResults(
    assessmentId: assessmentId,
    scope: scope,
    cursor: cursor,
    pageSize: pageSize,
  );

  @override
  Future<Result<AssessmentResult?>> getResultForStudent({
    required String assessmentId,
    required String studentId,
  }) => _dataSource.getCurrentResultForStudent(
    assessmentId: assessmentId,
    studentId: studentId,
  );

  @override
  Future<Result<AssessmentResult>> scoreSubmission(
    String omrId, {
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<OmrSubmission> submissionResult = await _omrRepository
        .getSubmission(omrId);
    if (submissionResult.isFailure) {
      return err(submissionResult.failureOrNull!);
    }
    final OmrSubmission submission = submissionResult.valueOrNull!;

    final Failure? canScoreDenial = OmrValidationPolicy.checkCanScore(
      submission,
    );
    if (canScoreDenial != null) {
      return err(canScoreDenial);
    }

    final Result<AssessmentSession> sessionResult = await _sessionRepository
        .getSession(submission.sessionId);
    if (sessionResult.isFailure) {
      return err(sessionResult.failureOrNull!);
    }
    final AssessmentSession session = sessionResult.valueOrNull!;

    final Result<Assessment> assessmentResult = await _assessmentRepository
        .getAssessment(submission.assessmentId);
    if (assessmentResult.isFailure) {
      return err(assessmentResult.failureOrNull!);
    }
    final Assessment assessment = assessmentResult.valueOrNull!;

    // The version this *sitting* was pinned to at start, not whatever is
    // currently published — a correction published mid-programme must not
    // silently change what an already-captured sheet is scored against
    // (`AssessmentSession.answerKeyVersion`'s own doc comment).
    final Result<AnswerKey> keyResult = await _assessmentRepository
        .getAnswerKeyVersion(
          submission.assessmentId,
          version: session.answerKeyVersion,
        );
    if (keyResult.isFailure) {
      return err(keyResult.failureOrNull!);
    }
    final AnswerKey answerKey = keyResult.valueOrNull!;

    final Result<List<OmrAnswer>> answersResult = await _omrRepository
        .getAnswers(omrId);
    if (answersResult.isFailure) {
      return err(answersResult.failureOrNull!);
    }

    final (:ScoringOutcome? outcome, :Failure? failure) = ScoringEngine.score(
      answers: answersResult.valueOrNull!,
      answerKey: answerKey,
      assessment: assessment,
    );
    if (failure != null) {
      return err(failure);
    }
    final ScoringOutcome scored = outcome!;

    final String? studentId = submission.studentId;
    if (studentId == null) {
      return err(
        const ValidationFailure(
          userMessage:
              'This sheet has no student identified yet and cannot be '
              'scored.',
          diagnostic: 'scoring attempted with no studentId',
        ),
      );
    }

    // Both narrow writes back onto the submission/answers happen before the
    // result is written, so a crash after this point still leaves the
    // machine evidence and the submission's own status correct — the result
    // itself is what a retry would still be missing, and retrying
    // `scoreSubmission` is idempotent by construction (supersession below).
    await _omrRepository.applyScoredAnswers(scored.scoredAnswers);
    await _omrRepository.markScored(
      omrId,
      answerKeyVersion: answerKey.version,
      machineScore: scored.machineMarksObtained,
      finalScore: scored.marksObtained,
    );

    final Result<AssessmentResult?> existingResult = await _dataSource
        .getCurrentResultForSubmission(omrId);
    if (existingResult.isFailure) {
      return err(existingResult.failureOrNull!);
    }
    final AssessmentResult? existing = existingResult.valueOrNull;

    final DateTime now = _clock.nowUtc();
    final AssessmentResult result = AssessmentResult(
      resultId: _idGenerator.newId(),
      studentId: studentId,
      assessmentId: submission.assessmentId,
      omrId: omrId,
      sessionId: submission.sessionId,
      schoolId: submission.schoolId,
      clusterId: submission.clusterId,
      districtId: submission.districtId,
      stateId: submission.stateId,
      academicYear: assessment.academicYear,
      grade: session.grade,
      section: session.section,
      answerKeyVersion: answerKey.version,
      totalMarks: scored.totalMarks,
      marksObtained: scored.marksObtained,
      correctCount: scored.correctCount,
      incorrectCount: scored.incorrectCount,
      blankCount: scored.blankCount,
      multipleMarkCount: scored.multipleMarkCount,
      scoredAt: now,
      scoredBy: actorUserId,
    );

    final Result<AssessmentResult> saveResult = await _dataSource.saveResult(
      result,
    );
    if (saveResult.isFailure) {
      return err(saveResult.failureOrNull!);
    }

    // The old row is never edited, only marked as superseded — Critical
    // Rule 5 applied to the one place a "re-score" could otherwise look like
    // a silent edit.
    if (existing != null) {
      await _dataSource.saveResult(existing.copyWithSupersededBy(result.resultId));
    }

    await _auditSink.record(
      AuditEvent(
        auditId: _idGenerator.newId(),
        userId: actorUserId,
        role: actorRole,
        action: existing == null
            ? AuditAction.scoreGenerated
            : AuditAction.scoreCorrected,
        entityType: 'result',
        entityId: result.resultId,
        timestamp: now,
        deviceId: _deviceInfo.deviceId,
        appVersion: _deviceInfo.appVersion,
        oldValue: existing == null
            ? null
            : <String, Object?>{
                'resultId': existing.resultId,
                'marksObtained': existing.marksObtained,
              },
        newValue: <String, Object?>{
          'marksObtained': result.marksObtained,
          'totalMarks': result.totalMarks,
          'answerKeyVersion': result.answerKeyVersion,
          'hasDiscrepancy': scored.hasDiscrepancy,
        },
      ),
    );

    return ok(result);
  }

  @override
  Future<Result<int>> ensureScored({
    required String assessmentId,
    required AccessScope scope,
    required String actorUserId,
    required String actorRole,
  }) async {
    int scoredCount = 0;
    Object? cursor;
    while (true) {
      final Result<Page<OmrSubmission>> pageResult = await _omrRepository
          .listSubmissionsForAssessment(
            assessmentId: assessmentId,
            scope: scope,
            cursor: cursor,
          );
      if (pageResult.isFailure) {
        return err(pageResult.failureOrNull!);
      }
      final Page<OmrSubmission> page = pageResult.valueOrNull!;

      for (final OmrSubmission submission in page.items) {
        if (!submission.readyForScoring) {
          continue;
        }
        final Result<AssessmentResult?> existing = await _dataSource
            .getCurrentResultForSubmission(submission.omrId);
        if (existing.isSuccess && existing.valueOrNull != null) {
          // Already has a current result — this sweep fills gaps, it is not
          // a re-score pass. A correction re-scores explicitly, elsewhere.
          continue;
        }
        final Result<AssessmentResult> scoreResult = await scoreSubmission(
          submission.omrId,
          actorUserId: actorUserId,
          actorRole: actorRole,
        );
        if (scoreResult.isSuccess) {
          scoredCount++;
        }
        // One sheet's scoring failure (a missing key entry, most likely)
        // must not stop the rest of the class from being scored.
      }

      if (!page.hasMore) {
        break;
      }
      cursor = page.nextCursor;
    }
    return ok(scoredCount);
  }
}
