/// Controller for the sync queue screen.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:natco_app/app/config/service_locator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';
import 'package:natco_app/features/sync/domain/repository/sync_queue_repository.dart';
import 'package:natco_app/features/sync/domain/service/sync_engine.dart';

final syncQueueProvider =
    FutureProvider.autoDispose<List<SyncQueueEntry>>((Ref ref) async {
  final SyncQueueRepository repo = ref.watch(syncQueueRepositoryProvider);
  final Result<List<SyncQueueEntry>> result = await repo.listQueue();
  return result.valueOr(<SyncQueueEntry>[]);
});

final syncControllerProvider =
    AsyncNotifierProvider<SyncController, void>(
        SyncController.new);

class SyncController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> retryFailed() async {
    state = const AsyncLoading<void>();
    final SyncEngine engine = ref.read(syncEngineProvider);
    await engine.syncNow();
    ref.invalidate(syncQueueProvider);
    state = const AsyncData<void>(null);
  }

  Future<void> keepServer(SyncQueueEntry entry, String userId, String role) async {
    state = const AsyncLoading<void>();
    final SyncQueueRepository repo = ref.read(syncQueueRepositoryProvider);
    await repo.keepServer(entry: entry, actorUserId: userId, actorRole: role);
    ref.invalidate(syncQueueProvider);
    state = const AsyncData<void>(null);
  }

  Future<void> keepLocal(SyncQueueEntry entry, String userId, String role) async {
    state = const AsyncLoading<void>();
    final SyncQueueRepository repo = ref.read(syncQueueRepositoryProvider);
    await repo.keepLocal(entry: entry, actorUserId: userId, actorRole: role);
    ref.invalidate(syncQueueProvider);
    state = const AsyncData<void>(null);
  }

  Future<void> createReviewCase(SyncQueueEntry entry, String userId, String role) async {
    state = const AsyncLoading<void>();
    final SyncQueueRepository repo = ref.read(syncQueueRepositoryProvider);
    await repo.createReviewCase(entry: entry, actorUserId: userId, actorRole: role);
    ref.invalidate(syncQueueProvider);
    state = const AsyncData<void>(null);
  }
}
