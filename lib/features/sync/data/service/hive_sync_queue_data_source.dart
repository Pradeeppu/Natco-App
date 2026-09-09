/// Hive implementation of the sync queue storage.
library;

import 'package:hive_ce/hive.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/sync/data/service/sync_queue_data_source.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';

final class HiveSyncQueueDataSource implements SyncQueueDataSource {
  const HiveSyncQueueDataSource(this._box);

  final Box<dynamic> _box;

  @override
  Future<Result<void>> enqueue(SyncQueueEntry entry) => guardAsync(() async {
        await _box.put(entry.syncId, entry.toJson());
      });

  @override
  Future<Result<List<SyncQueueEntry>>> listQueue() => guardAsync(() async {
        final List<SyncQueueEntry> entries = <SyncQueueEntry>[];
        for (final dynamic value in _box.values) {
          if (value is Map<dynamic, dynamic>) {
            final Map<String, Object?> json = value.map(
              (dynamic key, dynamic val) => MapEntry<String, Object?>(key.toString(), val),
            );
            final SyncQueueEntry? entry = SyncQueueEntry.tryFromJson(json);
            if (entry != null) {
              entries.add(entry);
            }
          }
        }
        return entries;
      });

  @override
  Future<Result<void>> updateEntry(SyncQueueEntry entry) => guardAsync(() async {
        if (!_box.containsKey(entry.syncId)) {
          throw StateError('SyncQueueEntry not found: ${entry.syncId}');
        }
        await _box.put(entry.syncId, entry.toJson());
      });

  @override
  Future<Result<void>> removeEntry(String syncId) => guardAsync(() async {
        await _box.delete(syncId);
      });
}
