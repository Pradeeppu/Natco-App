/// Interface for local queue access.
library;

import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';

abstract interface class SyncQueueDataSource {
  /// Writes a new entry to the queue.
  Future<Result<void>> enqueue(SyncQueueEntry entry);

  /// Retrieves the current items in the sync queue.
  Future<Result<List<SyncQueueEntry>>> listQueue();

  /// Updates an existing queue entry.
  Future<Result<void>> updateEntry(SyncQueueEntry entry);

  /// Removes an entry from the queue.
  Future<Result<void>> removeEntry(String syncId);
}
