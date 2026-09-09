/// The single [AssessmentRepository] implementation.
///
/// Composes a swappable [AssessmentDataSource] with [AnswerKeyPolicy], status
/// transition checks and audit logging — written once here rather than per
/// backend, mirroring `StudentRepositoryImpl`.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/pagination/page.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/assessments/data/service/assessment_data_source.dart';
import 'package:natco_app/features/assessments/domain/entity/answer_key.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment.dart';
import 'package:natco_app/features/assessments/domain/entity/assessment_assignment.dart';
import 'package:natco_app/features/assessments/domain/repository/assessment_repository.dart';
import 'package:natco_app/features/assessments/domain/service/answer_key_policy.dart';
import 'package:natco_app/features/auth/domain/entity/access_scope.dart';

final class AssessmentRepositoryImpl implements AssessmentRepository {
  AssessmentRepositoryImpl({
    required AssessmentDataSource dataSource,
    required AuditSink auditSink,
    required IdGenerator idGenerator,
    required Clock clock,
    required DeviceInfoService deviceInfo,
  }) : _dataSource = dataSource,
       _auditSink = auditSink,
       _idGenerator = idGenerator,
       _clock = clock,
       _deviceInfo = deviceInfo;

  final AssessmentDataSource _dataSource;
  final AuditSink _auditSink;
  final IdGenerator _idGenerator;
  final Clock _clock;
  final DeviceInfoService _deviceInfo;

  @override
  Future<Result<Page<Assessment>>> listAssessments({
    required AccessScope scope,
    String query = '',
    AssessmentStatus? status,
    Object? cursor,
    int pageSize = kDefaultPageSize,
  }) => _dataSource.listAssessments(
    scope: scope,
    query: query,
    status: status,
    cursor: cursor,
    pageSize: pageSize,
  );

  @override
  Future<Result<Assessment>> getAssessment(String assessmentId) =>
      _dataSource.getAssessment(assessmentId);

  @override
  Future<Result<Assessment>> createAssessment(
    Assessment assessment, {
    required String actorUserId,
    required String actorRole,
  }) async {
    if (assessment.totalQuestions < 1) {
      return err(
        const ValidationFailure(
          userMessage: 'An assessment needs at least one question.',
          fieldErrors: <String, String>{
            'totalQuestions': 'Enter how many questions the paper has.',
          },
          diagnostic: 'totalQuestions < 1',
        ),
      );
    }
    final Result<Assessment> result = await _dataSource.createAssessment(
      assessment,
    );
    if (result.isSuccess) {
      await _auditSink.record(
        _event(
          AuditAction.assessmentCreated,
          entityType: 'assessment',
          entityId: assessment.assessmentId,
          actorUserId: actorUserId,
          actorRole: actorRole,
          newValue: <String, Object?>{
            'status': assessment.status.wireName,
            'totalQuestions': assessment.totalQuestions,
          },
        ),
      );
    }
    return result;
  }

  @override
  Future<Result<Assessment>> updateAssessment(
    Assessment assessment, {
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<Assessment> currentResult = await _dataSource.getAssessment(
      assessment.assessmentId,
    );
    if (currentResult.isFailure) {
      return err(currentResult.failureOrNull!);
    }
    final Assessment current = currentResult.valueOrNull!;
    if (!current.status.isEditable) {
      // `totalQuestions` and `marksPerQuestion` are what every score was
      // computed from. Changing them under existing results would rewrite
      // marks nobody re-derived (Critical Rule 5's spirit, applied upstream).
      return err(
        ValidationFailure(
          userMessage:
              'This assessment is ${current.status.displayName.toLowerCase()} '
              'and can no longer be edited. To correct the answers, publish a '
              'new answer key version instead.',
          diagnostic: 'edit attempted on ${current.status.wireName}',
        ),
      );
    }

    final Result<Assessment> result = await _dataSource.updateAssessment(
      assessment.copyWith(updatedAt: _clock.nowUtc()),
    );
    if (result.isSuccess) {
      await _auditSink.record(
        _event(
          AuditAction.assessmentUpdated,
          entityType: 'assessment',
          entityId: assessment.assessmentId,
          actorUserId: actorUserId,
          actorRole: actorRole,
        ),
      );
    }
    return result;
  }

  @override
  Future<Result<Assessment>> changeStatus(
    String assessmentId, {
    required AssessmentStatus next,
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<Assessment> currentResult = await _dataSource.getAssessment(
      assessmentId,
    );
    if (currentResult.isFailure) {
      return err(currentResult.failureOrNull!);
    }
    final Assessment current = currentResult.valueOrNull!;

    if (!current.status.canTransitionTo(next)) {
      return err(
        IllegalStateTransitionFailure(
          entityType: 'assessment',
          from: current.status.wireName,
          to: next.wireName,
          diagnostic:
              '${current.status.wireName} cannot become ${next.wireName}',
        ),
      );
    }
    if (next == AssessmentStatus.published && !current.hasPublishedKey) {
      // Publishing an assessment with no key would let sessions start against
      // nothing, and every sheet would score zero with no visible cause.
      return err(
        const ValidationFailure(
          userMessage:
              'Publish the answer key first. Without one, every sheet would '
              'be scored against nothing.',
          diagnostic: 'publish attempted with no answer key',
        ),
      );
    }

    final Result<Assessment> result = await _dataSource.updateAssessment(
      current.copyWith(status: next, updatedAt: _clock.nowUtc()),
    );
    if (result.isSuccess) {
      await _auditSink.record(
        _event(
          AuditAction.assessmentStatusChanged,
          entityType: 'assessment',
          entityId: assessmentId,
          actorUserId: actorUserId,
          actorRole: actorRole,
          oldValue: <String, Object?>{'status': current.status.wireName},
          newValue: <String, Object?>{'status': next.wireName},
        ),
      );
    }
    return result;
  }

  // ------------------------------------------------------------ answer keys

  @override
  Future<Result<List<AnswerKey>>> listAnswerKeyVersions(String assessmentId) =>
      _dataSource.listAnswerKeys(assessmentId);

  @override
  Future<Result<AnswerKey?>> getPublishedAnswerKey(String assessmentId) async {
    final Result<List<AnswerKey>> keys = await _dataSource.listAnswerKeys(
      assessmentId,
    );
    return keys.map(
      (List<AnswerKey> all) => all
          .where((AnswerKey k) => k.isPublished)
          .fold<AnswerKey?>(
            null,
            (AnswerKey? best, AnswerKey k) =>
                best == null || k.version > best.version ? k : best,
          ),
    );
  }

  @override
  Future<Result<AnswerKey>> getAnswerKeyVersion(
    String assessmentId, {
    required int version,
  }) async {
    final Result<List<AnswerKey>> keys = await _dataSource.listAnswerKeys(
      assessmentId,
    );
    if (keys.isFailure) {
      return err(keys.failureOrNull!);
    }
    for (final AnswerKey key in keys.valueOrNull!) {
      if (key.version == version) {
        return ok(key);
      }
    }
    return err(
      NotFoundFailure(
        userMessage: 'That answer key version could not be found.',
        entityType: 'answer_key',
        entityId: '$assessmentId#v$version',
      ),
    );
  }

  @override
  Future<Result<AnswerKey>> getOrCreateDraftAnswerKey(
    String assessmentId, {
    required String actorUserId,
  }) async {
    final Result<List<AnswerKey>> keysResult = await _dataSource.listAnswerKeys(
      assessmentId,
    );
    if (keysResult.isFailure) {
      return err(keysResult.failureOrNull!);
    }
    final List<AnswerKey> keys = keysResult.valueOrNull!;
    for (final AnswerKey key in keys) {
      if (!key.isPublished) {
        return ok(key);
      }
    }
    if (keys.isNotEmpty) {
      // Every version is published, so there is nothing to edit. Opening a
      // correction is a deliberate act with a stated reason — `startCorrection`
      // — not something a screen does by navigating to the editor.
      return err(
        const ValidationFailure(
          userMessage:
              'Every answer key version is published. Start a correction to '
              'change an answer.',
          diagnostic: 'no draft key and none creatable implicitly',
        ),
      );
    }
    final AnswerKey draft = AnswerKey(
      answerKeyId: _idGenerator.newId(),
      assessmentId: assessmentId,
      version: 1,
      entries: const <AnswerKeyEntry>[],
      isPublished: false,
      createdBy: actorUserId,
      createdAt: _clock.nowUtc(),
    );
    return _dataSource.saveAnswerKey(draft);
  }

  @override
  Future<Result<AnswerKey>> saveDraftAnswerKey(
    AnswerKey key, {
    required String actorUserId,
    required String actorRole,
  }) async {
    final Failure? notEditable = AnswerKeyPolicy.checkEditable(key);
    if (notEditable != null) {
      return err(notEditable);
    }
    return _dataSource.saveAnswerKey(key);
  }

  @override
  Future<Result<AnswerKey>> publishAnswerKey(
    AnswerKey key, {
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<Assessment> assessmentResult = await _dataSource
        .getAssessment(key.assessmentId);
    if (assessmentResult.isFailure) {
      return err(assessmentResult.failureOrNull!);
    }
    final Assessment assessment = assessmentResult.valueOrNull!;

    final Failure? denial = AnswerKeyPolicy.checkPublishable(
      key: key,
      assessment: assessment,
    );
    if (denial != null) {
      return err(denial);
    }

    final DateTime now = _clock.nowUtc();
    final Result<AnswerKey> result = await _dataSource.publishAnswerKey(
      key.copyWith(isPublished: true, publishedAt: now),
    );
    if (result.isSuccess) {
      await _auditSink.record(
        _event(
          AuditAction.answerKeyPublished,
          entityType: 'answer_key',
          entityId: key.answerKeyId,
          actorUserId: actorUserId,
          actorRole: actorRole,
          newValue: <String, Object?>{
            'assessmentId': key.assessmentId,
            'version': key.version,
            'supersedesVersion': key.supersedesVersion,
            // The reason is the point of a correction's audit entry: without
            // it the record says a key changed but not why anyone decided so.
            'changeReason': key.changeReason,
          },
        ),
      );
    }
    return result;
  }

  @override
  Future<Result<AnswerKey>> startCorrection(
    String assessmentId, {
    required String changeReason,
    required String actorUserId,
    required String actorRole,
  }) async {
    if (changeReason.trim().isEmpty) {
      return err(
        const ValidationFailure(
          userMessage:
              'Say why this correction is needed. It is shown next to every '
              'result that gets re-scored.',
          fieldErrors: <String, String>{
            'changeReason': 'Enter a reason for the correction.',
          },
          diagnostic: 'correction started with no reason',
        ),
      );
    }
    final Result<AnswerKey?> publishedResult = await getPublishedAnswerKey(
      assessmentId,
    );
    if (publishedResult.isFailure) {
      return err(publishedResult.failureOrNull!);
    }
    final AnswerKey? published = publishedResult.valueOrNull;
    if (published == null) {
      return err(
        const ValidationFailure(
          userMessage:
              'There is no published answer key to correct yet. Edit the draft '
              'instead.',
          diagnostic: 'correction with no published key',
        ),
      );
    }

    final Result<List<AnswerKey>> allResult = await _dataSource.listAnswerKeys(
      assessmentId,
    );
    if (allResult.isFailure) {
      return err(allResult.failureOrNull!);
    }
    for (final AnswerKey key in allResult.valueOrNull!) {
      if (!key.isPublished) {
        // A correction is already open. Returning it rather than minting a
        // second one keeps versions contiguous — two open drafts would both
        // claim to be the next version and one would silently lose its edits.
        return ok(key);
      }
    }

    final AnswerKey next = AnswerKeyPolicy.nextVersion(
      published,
      answerKeyId: _idGenerator.newId(),
      changeReason: changeReason.trim(),
      createdBy: actorUserId,
      createdAt: _clock.nowUtc(),
    );
    final Result<AnswerKey> result = await _dataSource.saveAnswerKey(next);
    if (result.isSuccess) {
      await _auditSink.record(
        _event(
          AuditAction.answerKeyCorrectionStarted,
          entityType: 'answer_key',
          entityId: next.answerKeyId,
          actorUserId: actorUserId,
          actorRole: actorRole,
          newValue: <String, Object?>{
            'assessmentId': assessmentId,
            'version': next.version,
            'supersedesVersion': published.version,
            'changeReason': next.changeReason,
          },
        ),
      );
    }
    return result;
  }

  // ------------------------------------------------------------ assignments

  @override
  Future<Result<List<AssessmentAssignment>>> listAssignments(
    String assessmentId,
  ) => _dataSource.listAssignments(assessmentId);

  @override
  Future<Result<AssessmentAssignment>> assign(
    AssessmentAssignment assignment, {
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<AssessmentAssignment> result = await _dataSource
        .saveAssignment(assignment);
    if (result.isSuccess) {
      await _auditSink.record(
        _event(
          AuditAction.assessmentAssigned,
          entityType: 'assessment_assignment',
          entityId: assignment.assignmentId,
          actorUserId: actorUserId,
          actorRole: actorRole,
          newValue: <String, Object?>{
            'assessmentId': assignment.assessmentId,
            'schoolId': assignment.schoolId,
            'grade': assignment.grade,
          },
        ),
      );
    }
    return result;
  }

  @override
  Future<Result<void>> unassign(
    String assignmentId, {
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<void> result = await _dataSource.deleteAssignment(
      assignmentId,
    );
    if (result.isSuccess) {
      await _auditSink.record(
        _event(
          AuditAction.assessmentUnassigned,
          entityType: 'assessment_assignment',
          entityId: assignmentId,
          actorUserId: actorUserId,
          actorRole: actorRole,
        ),
      );
    }
    return result;
  }

  AuditEvent _event(
    AuditAction action, {
    required String entityType,
    required String entityId,
    required String actorUserId,
    required String actorRole,
    Map<String, Object?>? oldValue,
    Map<String, Object?>? newValue,
  }) => AuditEvent(
    auditId: _idGenerator.newId(),
    userId: actorUserId,
    role: actorRole,
    action: action,
    entityType: entityType,
    entityId: entityId,
    timestamp: _clock.nowUtc(),
    deviceId: _deviceInfo.deviceId,
    appVersion: _deviceInfo.appVersion,
    oldValue: oldValue,
    newValue: newValue,
  );
}
