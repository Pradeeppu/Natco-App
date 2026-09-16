import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';
import 'package:natco_app/features/sync/domain/repository/sync_queue_repository.dart';

class DummySyncQueueRepository implements SyncQueueRepository {
  @override
  Future<Result<void>> enqueue(SyncQueueEntry entry) async => ok(null);
  @override
  Future<Result<List<SyncQueueEntry>>> listQueue() async => ok([]);
  @override
  Future<Result<void>> updateEntry(SyncQueueEntry entry) async => ok(null);
  @override
  Future<Result<void>> removeEntry(String syncId) async => ok(null);
  @override
  Future<Result<void>> keepLocal({required SyncQueueEntry entry, required dynamic authorization}) async => ok(null);
  @override
  Future<Result<void>> keepServer({required SyncQueueEntry entry, required dynamic authorization}) async => ok(null);
  @override
  Future<Result<void>> createReviewCase({required SyncQueueEntry entry, required dynamic authorization}) async => ok(null);
}
