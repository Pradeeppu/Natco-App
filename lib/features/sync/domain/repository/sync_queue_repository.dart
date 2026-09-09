/// Repository interface for interacting with the sync queue.
library;

import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';

abstract interface class SyncQueueRepository {
  /// Enqueues a new operation to be synced.
  Future<Result<void>> enqueue(SyncQueueEntry entry);

  /// Retrieves the current items in the sync queue.
  Future<Result<List<SyncQueueEntry>>> listQueue();

  /// Updates an existing queue entry.
  Future<Result<void>> updateEntry(SyncQueueEntry entry);

  /// Removes an entry from the queue.
  Future<Result<void>> removeEntry(String syncId);

  /// Overwrites the server's version with the local payload.
  Future<Result<void>> keepLocal({
    required SyncQueueEntry entry,
    required String actorUserId,
    required String actorRole,
  });

  /// Overwrites the local version with the server's payload, discarding the
  /// local changes.
  Future<Result<void>> keepServer({
    required SyncQueueEntry entry,
    required String actorUserId,
    required String actorRole,
  });

  /// Escalates the conflict to a supervisor review case without resolving it.
  Future<Result<void>> createReviewCase({
    required SyncQueueEntry entry,
    required String actorUserId,
    required String actorRole,
  });
}
