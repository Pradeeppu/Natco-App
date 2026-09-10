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

/// After this many failed attempts, an entry stops auto-retrying and
/// surfaces under "Retry Failed Uploads" for a person to look at
/// (docs/06-offline-sync-strategy.md §3).
const int kMaxAutoRetryAttempts = 8;

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
  ///
  /// Drains `PENDING` entries only. A `FAILED` entry — whether it stopped
  /// because of a permission/validation error, or because it hit
  /// [kMaxAutoRetryAttempts] — is deliberately excluded: this is what makes
  /// "stops auto-retrying" true. Called by the periodic timer, on reconnect,
  /// and on app resume (docs/06-offline-sync-strategy.md §7); none of those
  /// should ever re-touch an entry that has already surfaced to a person.
  Future<void> syncNow() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      await _drainQueue();
    } finally {
      _isSyncing = false;
    }
  }

  /// The explicit "Retry Failed Uploads" action. Resets every currently
  /// `FAILED` entry back to `PENDING` — clearing `nextAttemptAt` and the
  /// error fields, so it gets a fresh attempt rather than one still carrying
  /// the reason it stopped — then drains normally.
  ///
  /// This is the one path allowed to re-touch a stopped entry, and it is
  /// exactly the boundary docs/06 §3 draws: automatic drain never resurrects
  /// what stopped; a person choosing to retry does.
  Future<void> retryFailedNow() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final Result<List<SyncQueueEntry>> queueResult = await _queueRepository
          .listQueue();
      if (queueResult.isSuccess) {
        for (final SyncQueueEntry entry in queueResult.valueOrNull!) {
          if (entry.status == SyncStatus.failed) {
            await _queueRepository.updateEntry(
              entry.copyWith(
                status: SyncStatus.pending,
                // A fresh set of attempts, not one more attempt against a
                // counter already at the cap — otherwise an entry that hit
                // `kMaxAutoRetryAttempts` would fail straight back to
                // `FAILED` after a single retry, which would make this
                // button look broken rather than genuinely give it another
                // run.
                attemptCount: 0,
                clearError: true,
                clearNextAttemptAt: true,
              ),
            );
          }
        }
      }
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

    // Filter to only entries that are ready to sync. `FAILED` is
    // deliberately not included — see `syncNow`'s doc.
    final List<SyncQueueEntry> readyEntries = entries.where((SyncQueueEntry e) {
      if (e.status != SyncStatus.pending) return false;
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

    // Transient or Auth.
    //
    // `attemptCount` is never capped into a drop (docs/06-offline-sync-
    // strategy.md §3: "the queue has no eviction policy") — but it does stop
    // *auto*-retrying after `kMaxAutoRetryAttempts`, and surfaces under
    // "Retry Failed Uploads" instead. Without this an entry retrying against
    // a permanently unreachable device would back off forever at the 30-
    // minute ceiling and never visibly become something a person needs to
    // look at.
    if (entry.attemptCount >= kMaxAutoRetryAttempts) {
      await _queueRepository.updateEntry(
        entry.copyWith(status: SyncStatus.failed, errorMessage: failure.diagnostic),
      );
      return;
    }

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
