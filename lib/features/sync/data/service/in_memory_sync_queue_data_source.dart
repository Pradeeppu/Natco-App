/// In-memory [SyncQueueDataSource]. Backs demo mode and tests — mirrors
/// `InMemoryResultDataSource`'s pattern rather than routing every repository
/// write's new `enqueue` call through a real Hive box that demo/test mode
/// never opens.
library;

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/sync/data/service/sync_queue_data_source.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';

final class InMemorySyncQueueDataSource implements SyncQueueDataSource {
  InMemorySyncQueueDataSource({List<SyncQueueEntry> entries = const <SyncQueueEntry>[]})
    : _entries = <String, SyncQueueEntry>{
        for (final SyncQueueEntry e in entries) e.syncId: e,
      };

  final Map<String, SyncQueueEntry> _entries;

  @override
  Future<Result<void>> enqueue(SyncQueueEntry entry) async {
    _entries[entry.syncId] = entry;
    return ok(null);
  }

  @override
  Future<Result<List<SyncQueueEntry>>> listQueue() async =>
      ok(_entries.values.toList(growable: false));

  @override
  Future<Result<void>> updateEntry(SyncQueueEntry entry) async {
    if (!_entries.containsKey(entry.syncId)) {
      return err(
        NotFoundFailure(
          userMessage: 'That sync queue entry could not be found.',
          entityType: 'sync_queue_entry',
          entityId: entry.syncId,
        ),
      );
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
