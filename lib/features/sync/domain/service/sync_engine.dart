/// Background engine that drains the sync queue.
library;

import 'dart:async';
import 'dart:math';

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';
import 'package:natco_app/features/sync/domain/entity/sync_status.dart';
import 'package:natco_app/features/sync/domain/repository/sync_queue_repository.dart';

abstract interface class SyncBackendService {
  /// Pushes a payload to the backend with an idempotency key.
  Future<Result<void>> syncPayload({
    required String entityType,
    required String operation,
    required String payloadRef,
    required String idempotencyKey,
  });
}

final class SyncEngine {
  SyncEngine({
    required SyncQueueRepository queueRepository,
    required SyncBackendService backend,
    required Clock clock,
  })  : _queueRepository = queueRepository,
        _backend = backend,
        _clock = clock,
        _random = Random();

  final SyncQueueRepository _queueRepository;
  final SyncBackendService _backend;
  final Clock _clock;
  final Random _random;

  bool _isSyncing = false;

  /// Dependency order for draining the queue.
  static const List<String> _dependencyOrder = <String>[
    'session',
    'omr_submission',
    'omr_answers',
    'omr_validations',
    'file_upload',
  ];

  /// Starts the sync process. If already syncing, does nothing.
  Future<void> syncNow() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      await _drainQueue();
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _drainQueue() async {
    final Result<List<SyncQueueEntry>> queueResult = await _queueRepository.listQueue();
    if (queueResult.isFailure) return;

    final List<SyncQueueEntry> entries = queueResult.valueOrNull!;
    final DateTime now = _clock.nowUtc();

    // Filter to only entries that are ready to sync
    final List<SyncQueueEntry> readyEntries = entries.where((SyncQueueEntry e) {
      if (e.status != SyncStatus.pending && e.status != SyncStatus.failed) return false;
      if (e.nextAttemptAt != null && e.nextAttemptAt!.isAfter(now)) return false;
      return true;
    }).toList();

    // Sort by dependency order first, then by creation date.
    readyEntries.sort((SyncQueueEntry a, SyncQueueEntry b) {
      final int orderA = _dependencyOrder.indexOf(a.entityType);
      final int orderB = _dependencyOrder.indexOf(b.entityType);
      final int resolvedA = orderA == -1 ? 99 : orderA;
      final int resolvedB = orderB == -1 ? 99 : orderB;
      
      if (resolvedA != resolvedB) {
        return resolvedA.compareTo(resolvedB);
      }
      return a.createdAt.compareTo(b.createdAt);
    });

    for (final SyncQueueEntry entry in readyEntries) {
      await _processEntry(entry);
    }
  }

  Future<void> _processEntry(SyncQueueEntry entry) async {
    // Mark as uploading
    final SyncQueueEntry uploadingEntry = entry.copyWith(
      status: SyncStatus.uploading,
      lastAttemptAt: _clock.nowUtc(),
      attemptCount: entry.attemptCount + 1,
    );
    await _queueRepository.updateEntry(uploadingEntry);

    // Attempt to sync via backend
    final Result<void> result = await _backend.syncPayload(
      entityType: uploadingEntry.entityType,
      operation: uploadingEntry.operation,
      payloadRef: uploadingEntry.payloadRef,
      idempotencyKey: uploadingEntry.idempotencyKey,
    );

    switch (result) {
      case Success<void>():
        await _queueRepository.updateEntry(
          uploadingEntry.copyWith(status: SyncStatus.synced),
        );

      case FailureResult<void>(:final Failure failure):
        await _handleFailure(uploadingEntry, failure);
    }
  }

  Future<void> _handleFailure(SyncQueueEntry entry, Failure failure) async {
    // Error classification
    // transient, auth, permission, validation, conflict
    final bool isPermission = failure is PermissionFailure;
    final bool isValidation = failure is ValidationFailure;
    final bool isConflict = failure is ConflictFailure;

    if (isConflict) {
      await _queueRepository.updateEntry(
        entry.copyWith(
          status: SyncStatus.conflict,
          errorMessage: failure.diagnostic,
        ),
      );
      return;
    }

    if (isPermission || isValidation) {
      await _queueRepository.updateEntry(
        entry.copyWith(
          status: SyncStatus.failed,
          errorMessage: failure.diagnostic,
          // Do not set nextAttemptAt, effectively stops retrying
        ),
      );
      return;
    }

    // Transient or Auth
    final DateTime now = _clock.nowUtc();
    final Duration backoff = _calculateBackoff(entry.attemptCount);
    
    await _queueRepository.updateEntry(
      entry.copyWith(
        status: SyncStatus.pending, // Keep as pending/failed to be picked up
        errorMessage: failure.diagnostic,
        nextAttemptAt: now.add(backoff),
      ),
    );
  }

  Duration _calculateBackoff(int attemptCount) {
    // delay = min(2^attemptCount * 5s, 30min) ± 20% jitter
    final num exponential = pow(2, attemptCount) * 5;
    final int delaySeconds = min(exponential.toInt(), 30 * 60); // Max 30 min

    final double jitterMultiplier = 0.8 + (_random.nextDouble() * 0.4); // 0.8 to 1.2
    final int finalSeconds = (delaySeconds * jitterMultiplier).round();

    return Duration(seconds: finalSeconds);
  }
}
