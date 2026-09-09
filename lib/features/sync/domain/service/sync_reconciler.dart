/// Runs on launch before UI is interactive to recover from crashes.
library;

import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';
import 'package:natco_app/features/sync/domain/entity/sync_status.dart';
import 'package:natco_app/features/sync/domain/repository/sync_queue_repository.dart';

final class SyncReconciler {
  const SyncReconciler({
    required SyncQueueRepository queueRepository,
  })  : _queueRepository = queueRepository;

  final SyncQueueRepository _queueRepository;

  Future<void> reconcile() async {
    final Result<List<SyncQueueEntry>> queueResult = await _queueRepository.listQueue();
    if (queueResult.isFailure) return;

    final List<SyncQueueEntry> entries = queueResult.valueOrNull!;

    for (final SyncQueueEntry entry in entries) {
      // Any entry stuck in UPLOADING reset to PENDING
      if (entry.status == SyncStatus.uploading) {
        await _queueRepository.updateEntry(
          entry.copyWith(status: SyncStatus.pending),
        );
      }
    }

    // TODO: Step 1 (re-enqueue orphans) and Step 3 (re-run processing)
    // belong here once the actual entities (submissions) can be queried from
    // the local database. Since this phase focuses on the sync engine, we stub
    // the specific image evidence missing check logic here.

    // 4. Any submission whose image file is missing -> mark UNREADABLE_EVIDENCE_MISSING
    // Example stub (simulating finding a captured submission and checking its image)
    // if (!_fileSystem.fileExistsSync(imagePath)) {
    //   _auditSink.record(...)
    //   return err(ValidationFailure(diagnostic: 'UNREADABLE_EVIDENCE_MISSING'));
    // }
  }
}
