/// Proves `kMaxAutoRetryAttempts` actually stops auto-retry rather than
/// backing off forever (docs/06-offline-sync-strategy.md §3: "the queue has
/// no eviction policy" — but it must stop retrying automatically and surface
/// to a person).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/sync/data/repository/sync_queue_repository_impl.dart';
import 'package:natco_app/features/sync/data/service/sync_queue_data_source.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';
import 'package:natco_app/features/sync/domain/entity/sync_status.dart';
import 'package:natco_app/features/sync/domain/service/sync_conflict_policy.dart';
import 'package:natco_app/features/sync/domain/service/sync_engine.dart';

final class _InMemoryQueueDataSource implements SyncQueueDataSource {
  final Map<String, SyncQueueEntry> _entries = <String, SyncQueueEntry>{};

  @override
  Future<Result<void>> enqueue(SyncQueueEntry entry) async {
    _entries[entry.syncId] = entry;
    return ok(null);
  }

  @override
  Future<Result<List<SyncQueueEntry>>> listQueue() async =>
      ok(_entries.values.toList());

  @override
  Future<Result<void>> updateEntry(SyncQueueEntry entry) async {
    _entries[entry.syncId] = entry;
    return ok(null);
  }

  @override
  Future<Result<void>> removeEntry(String syncId) async {
    _entries.remove(syncId);
    return ok(null);
  }
}

/// A backend that never succeeds — a permanently unreachable device, not a
/// one-off dropped connection.
final class _AlwaysUnreachableBackend implements SyncBackendService {
  int callCount = 0;

  @override
  Future<Result<void>> syncPayload({
    required String entityType,
    required String operation,
    required String payloadRef,
    required String idempotencyKey,
  }) async {
    callCount++;
    return err(NetworkFailure.unreachable(diagnostic: 'permanently offline'));
  }
}

void main() {
  test(
    'an entry that keeps failing stops auto-retrying after '
    'kMaxAutoRetryAttempts and surfaces as FAILED',
    () async {
      final SyncQueueRepositoryImpl repository = SyncQueueRepositoryImpl(
        dataSource: _InMemoryQueueDataSource(),
        conflictPolicy: const SyncConflictPolicy(),
        auditSink: InMemoryAuditSink(),
        idGenerator: const UuidIdGenerator(),
        clock: const SystemClock(),
        deviceInfo: const StaticDeviceInfoService(),
      );
      final _AlwaysUnreachableBackend backend = _AlwaysUnreachableBackend();
      final SyncEngine engine = SyncEngine(
        queueRepository: repository,
        backend: backend,
        clock: const SystemClock(),
      );

      await repository.enqueue(
        SyncQueueEntry(
          syncId: 'sync_1',
          entityType: 'omr_submission',
          entityId: 'sub_1',
          operation: 'create',
          payloadRef: 'ref_1',
          idempotencyKey: 'idem_1',
          createdAt: DateTime.utc(2026),
          attemptCount: 0,
          status: SyncStatus.pending,
        ),
      );

      // Drive it past the cap. Each call backs the entry's `nextAttemptAt`
      // off into the future, so it is force-cleared between attempts —
      // the test is proving the attempt-count cap, not waiting out backoff.
      for (int i = 0; i <= kMaxAutoRetryAttempts; i++) {
        await engine.syncNow();
        final SyncQueueEntry current = (await repository.listQueue())
            .valueOrNull!
            .single;
        if (current.status == SyncStatus.failed) {
          break;
        }
        await repository.updateEntry(
          current.copyWith(nextAttemptAt: DateTime.utc(2000)),
        );
      }

      final SyncQueueEntry finalEntry = (await repository.listQueue())
          .valueOrNull!
          .single;
      expect(finalEntry.status, SyncStatus.failed);
      expect(finalEntry.attemptCount, kMaxAutoRetryAttempts);
      // Never dropped — docs/06 §3: "the queue has no eviction policy".
      expect((await repository.listQueue()).valueOrNull, hasLength(1));

      // The call count right after the cap trips, so the next assertions
      // are about calls made *after* this point.
      final int callsAtCap = backend.callCount;

      // A stopped entry must not be silently retried by the ordinary
      // automatic path — the periodic timer, a reconnect, or app resume all
      // call `syncNow()` (docs/06 §7), and none of those should re-touch
      // something that already surfaced to a person.
      await engine.syncNow();
      await engine.syncNow();
      expect(
        backend.callCount,
        callsAtCap,
        reason:
            'a FAILED entry must not be picked up by automatic syncNow() — '
            'that is what "stops auto-retrying" has to mean',
      );
      expect(
        (await repository.listQueue()).valueOrNull!.single.status,
        SyncStatus.failed,
      );

      // The explicit "Retry Failed Uploads" action is the one path allowed
      // to bring it back — with a genuinely fresh attempt count, not one
      // more attempt against a counter already at the cap.
      await engine.retryFailedNow();
      expect(backend.callCount, callsAtCap + 1);
      final SyncQueueEntry afterRetry = (await repository.listQueue())
          .valueOrNull!
          .single;
      // One attempt back off below the cap, not straight back to FAILED —
      // proof `attemptCount` genuinely reset rather than resuming at 8.
      expect(afterRetry.status, SyncStatus.pending);
      expect(afterRetry.attemptCount, 1);
    },
  );
}
