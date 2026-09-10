import 'package:flutter_test/flutter_test.dart';
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

import 'fault_injecting_sync_backend_fake.dart';

// A simple in-memory queue for testing
final class _InMemoryQueueDataSource implements SyncQueueDataSource {
  final Map<String, SyncQueueEntry> _entries = <String, SyncQueueEntry>{};

  @override
  Future<Result<void>> enqueue(SyncQueueEntry entry) async {
    _entries[entry.syncId] = entry;
    return ok(null);
  }

  @override
  Future<Result<List<SyncQueueEntry>>> listQueue() async {
    return ok(_entries.values.toList());
  }

  @override
  Future<Result<void>> updateEntry(SyncQueueEntry entry) async {
    if (!_entries.containsKey(entry.syncId)) {
      throw StateError('Entry not found');
    }
    _entries[entry.syncId] = entry;
    return ok(null);
  }

  @override
  Future<Result<void>> removeEntry(String syncId) async {
    _entries.remove(syncId);
    return ok(null);
  }
}

void main() {
  group('SyncEngine', () {
    test('killing app mid-upload produces exactly one server record via idempotency', () async {
      // 1. Arrange
      final SyncQueueDataSource dataSource = _InMemoryQueueDataSource();
      final FaultInjectingSyncBackendFake backend = FaultInjectingSyncBackendFake();
      
      final SyncQueueRepositoryImpl repository = SyncQueueRepositoryImpl(
        dataSource: dataSource,
        conflictPolicy: const SyncConflictPolicy(),
        auditSink: InMemoryAuditSink(),
        idGenerator: const UuidIdGenerator(),
        clock: const SystemClock(),
        deviceInfo: const StaticDeviceInfoService(),
      );

      final SyncEngine engine = SyncEngine(
        queueRepository: repository,
        backend: backend,
        clock: const SystemClock(),
      );

      // Create a pending entry
      final SyncQueueEntry entry = SyncQueueEntry(
        syncId: 'sync_1',
        entityType: SyncEntityType.omrSubmission,
        entityId: 'sub_1',
        operation: SyncOperation.create,
        payloadRef: 'ref_1',
        idempotencyKey: 'idem_1',
        createdAt: DateTime.utc(2026, 9, 9),
        attemptCount: 0,
        status: SyncStatus.pending,
      );

      await repository.enqueue(entry);

      // Program the fake backend to drop the network connection AFTER processing
      backend.failNextNetworkCall = true;

      // 2. Act - First attempt
      await engine.syncNow();

      // Verify it failed locally (client thinks it failed)
      final List<SyncQueueEntry> queueAfterFirst = (await repository.listQueue()).valueOrNull!;
      final SyncQueueEntry entryAfterFirst = queueAfterFirst.first;
      
      expect(entryAfterFirst.status, equals(SyncStatus.pending)); // It backed off
      expect(entryAfterFirst.attemptCount, equals(1));
      expect(backend.successfulWrites, equals(1)); // Server ACTUALLY processed it
      expect(backend.idempotencyShortCircuitCount, equals(0));

      // Reset the time constraint for the next attempt so engine picks it up again
      // by setting nextAttemptAt to past
      await repository.updateEntry(
        entryAfterFirst.copyWith(nextAttemptAt: DateTime.utc(2000)),
      );

      // 3. Act - Second attempt (simulating an app restart/retry)
      await engine.syncNow();

      // 4. Assert
      final List<SyncQueueEntry> queueAfterSecond = (await repository.listQueue()).valueOrNull!;
      final SyncQueueEntry entryAfterSecond = queueAfterSecond.first;

      // Client now sees it as synced
      expect(entryAfterSecond.status, equals(SyncStatus.synced));
      
      // Total writes to the logical DB is STILL 1
      expect(backend.successfulWrites, equals(1));
      
      // The idempotency key short-circuited the second attempt
      expect(backend.idempotencyShortCircuitCount, equals(1));
    });
  });
}
