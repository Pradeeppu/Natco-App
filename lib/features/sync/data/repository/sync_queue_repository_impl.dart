/// Implementation of the sync queue repository.
library;

import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/auth/domain/entity/user_role.dart';
import 'package:natco_app/features/sync/data/service/sync_queue_data_source.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';
import 'package:natco_app/features/sync/domain/entity/sync_status.dart';
import 'package:natco_app/features/sync/domain/repository/sync_queue_repository.dart';
import 'package:natco_app/features/sync/domain/service/sync_conflict_policy.dart';

final class SyncQueueRepositoryImpl implements SyncQueueRepository {
  SyncQueueRepositoryImpl({
    required SyncQueueDataSource dataSource,
    required SyncConflictPolicy conflictPolicy,
    required AuditSink auditSink,
    required IdGenerator idGenerator,
    required Clock clock,
    required DeviceInfoService deviceInfo,
  })  : _dataSource = dataSource,
        _conflictPolicy = conflictPolicy,
        _auditSink = auditSink,
        _idGenerator = idGenerator,
        _clock = clock,
        _deviceInfo = deviceInfo;

  final SyncQueueDataSource _dataSource;
  final SyncConflictPolicy _conflictPolicy;
  final AuditSink _auditSink;
  final IdGenerator _idGenerator;
  final Clock _clock;
  final DeviceInfoService _deviceInfo;

  @override
  Future<Result<void>> enqueue(SyncQueueEntry entry) =>
      _dataSource.enqueue(entry);

  @override
  Future<Result<List<SyncQueueEntry>>> listQueue() => _dataSource.listQueue();

  @override
  Future<Result<void>> updateEntry(SyncQueueEntry entry) =>
      _dataSource.updateEntry(entry);

  @override
  Future<Result<void>> removeEntry(String syncId) =>
      _dataSource.removeEntry(syncId);

  @override
  Future<Result<void>> keepLocal({
    required SyncQueueEntry entry,
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<void> authResult = _conflictPolicy.canResolve(
      actorRole: UserRole.tryFromWireName(actorRole) ?? UserRole.pstTeacher,
      entityType: entry.entityType,
      isEscalation: false,
    );
    if (authResult.isFailure) return authResult;

    // In a real implementation this would re-base the payload.
    // For now we simulate success and log audit.
    await _auditSink.record(
      _event(
        AuditAction.syncConflictResolved,
        entityId: entry.syncId,
        actorUserId: actorUserId,
        actorRole: actorRole,
        newValue: <String, Object?>{'resolution': 'KEEP_LOCAL'},
      ),
    );

    // Reset status to pending so engine picks it up again
    final SyncQueueEntry updated = entry.copyWith(
      status: SyncStatus.pending,
      errorMessage: null,
      errorCode: null,
    );
    return _dataSource.updateEntry(updated);
  }

  @override
  Future<Result<void>> keepServer({
    required SyncQueueEntry entry,
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<void> authResult = _conflictPolicy.canResolve(
      actorRole: UserRole.tryFromWireName(actorRole) ?? UserRole.pstTeacher,
      entityType: entry.entityType,
      isEscalation: false,
    );
    if (authResult.isFailure) return authResult;

    await _auditSink.record(
      _event(
        AuditAction.syncConflictResolved,
        entityId: entry.syncId,
        actorUserId: actorUserId,
        actorRole: actorRole,
        newValue: <String, Object?>{'resolution': 'KEEP_SERVER'},
      ),
    );

    // Server wins, so we discard the local intent. We mark as synced.
    final SyncQueueEntry updated = entry.copyWith(
      status: SyncStatus.synced,
      errorMessage: null,
      errorCode: null,
    );
    return _dataSource.updateEntry(updated);
  }

  @override
  Future<Result<void>> createReviewCase({
    required SyncQueueEntry entry,
    required String actorUserId,
    required String actorRole,
  }) async {
    final Result<void> authResult = _conflictPolicy.canResolve(
      actorRole: UserRole.tryFromWireName(actorRole) ?? UserRole.pstTeacher,
      entityType: entry.entityType,
      isEscalation: true,
    );
    if (authResult.isFailure) return authResult;

    await _auditSink.record(
      _event(
        AuditAction.syncConflictResolved,
        entityId: entry.syncId,
        actorUserId: actorUserId,
        actorRole: actorRole,
        newValue: <String, Object?>{'resolution': 'REVIEW_CASE'},
      ),
    );

    // Moves it out of conflict state into a terminal state (or specialized review state)
    // Here we mark it as FAILED with a specific error so it stops prompting the user.
    final SyncQueueEntry updated = entry.copyWith(
      status: SyncStatus.failed,
      errorMessage: 'Escalated to a Review Case',
      errorCode: 'REVIEW_CASE',
    );
    return _dataSource.updateEntry(updated);
  }

  AuditEvent _event(
    AuditAction action, {
    required String entityId,
    required String actorUserId,
    required String actorRole,
    Map<String, Object?>? newValue,
  }) => AuditEvent(
    auditId: _idGenerator.newId(),
    userId: actorUserId,
    role: actorRole,
    action: action,
    entityType: 'sync_queue',
    entityId: entityId,
    timestamp: _clock.nowUtc(),
    deviceId: _deviceInfo.deviceId,
    appVersion: _deviceInfo.appVersion,
    newValue: newValue,
  );
}
