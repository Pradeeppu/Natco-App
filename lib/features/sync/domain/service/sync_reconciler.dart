/// Runs on launch, before the UI is interactive, to recover from a crash
/// (docs/06-offline-sync-strategy.md §4).
///
/// Four steps in the doc; two are here.
///
/// 1. **Re-enqueue an orphaned entity** (a non-terminal entity with no queue
///    record) — genuinely not implementable yet. Nothing in this codebase
///    currently *writes* an entity without also writing its queue entry in
///    the same step (that write-path only exists once phase 5's capture flow
///    does), so there is no code path today that could produce an orphan to
///    re-enqueue. Building this now would mean inventing the very
///    integration phase 5 has not landed, against no real caller to prove it
///    against.
/// 2. **Reset a stuck `UPLOADING` entry to `PENDING`** — done below. The
///    entry's idempotency key is what makes the resulting retry safe
///    (`SyncEngine`'s own doc explains why).
/// 3. **Re-run processing for a `CAPTURED`/`PROCESSING` submission with its
///    image still on disk** — done below, as far as it can be without a
///    processing pipeline to hand off to (phase 6): a submission stuck in
///    `PROCESSING` (a crash mid-run) is reset to `CAPTURED`, a clean state
///    phase 6's pipeline can pick up from scratch rather than resuming a
///    partial run that does not exist. A submission already sitting in
///    `CAPTURED` needs nothing done to it — it is already exactly where
///    processing would find it.
/// 4. **Mark a submission `UNREADABLE_EVIDENCE_MISSING` when its image file
///    is gone** — done below, and audited rather than silently dropped. This
///    is the step that admits the loss honestly instead of hiding it.
library;

import 'package:natco_app/core/services/file_system_service.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_validation/domain/repository/omr_validation_repository.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';
import 'package:natco_app/features/sync/domain/entity/sync_status.dart';
import 'package:natco_app/features/sync/domain/repository/sync_queue_repository.dart';

final class SyncReconciler {
  const SyncReconciler({
    required SyncQueueRepository queueRepository,
    required OmrValidationRepository omrRepository,
    required FileSystemService fileSystem,
  }) : _queueRepository = queueRepository,
       _omrRepository = omrRepository,
       _fileSystem = fileSystem;

  final SyncQueueRepository _queueRepository;
  final OmrValidationRepository _omrRepository;
  final FileSystemService _fileSystem;

  Future<void> reconcile() async {
    await _resetStuckUploads();
    await _reconcileUnfinishedSubmissions();
  }

  Future<void> _resetStuckUploads() async {
    final Result<List<SyncQueueEntry>> queueResult = await _queueRepository
        .listQueue();
    if (queueResult.isFailure) {
      return;
    }
    for (final SyncQueueEntry entry in queueResult.valueOrNull!) {
      if (entry.status == SyncStatus.uploading) {
        await _queueRepository.updateEntry(
          entry.copyWith(status: SyncStatus.pending),
        );
      }
    }
  }

  Future<void> _reconcileUnfinishedSubmissions() async {
    final Result<List<OmrSubmission>> unfinished = await _omrRepository
        .listCapturedOrProcessing();
    if (unfinished.isFailure) {
      return;
    }
    for (final OmrSubmission submission in unfinished.valueOrNull!) {
      if (!_fileSystem.fileExistsSync(submission.originalImagePath)) {
        // Step 4. Never silently dropped — the record stays, and
        // `OmrValidationRepositoryImpl.markEvidenceMissing` audits the
        // finding so a Supervisor can see it under `reviewExceptions`.
        await _omrRepository.markEvidenceMissing(submission.omrId);
        continue;
      }
      // Step 3. Only a genuinely stuck `PROCESSING` submission is touched;
      // `resetToCaptured` itself is a no-op for one already `CAPTURED`.
      await _omrRepository.resetToCaptured(submission.omrId);
    }
  }
}
