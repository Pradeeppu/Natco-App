/// Tests for [SyncReconciler] — the crash-recovery pass that runs at launch
/// (docs/06-offline-sync-strategy.md §4).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/core/services/audit_sink.dart';
import 'package:natco_app/core/services/device_info_service.dart';
import 'package:natco_app/core/services/file_system_service.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/core/utils/id_generator.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:natco_app/features/omr_processing/domain/entity/image_quality_report.dart';
import 'package:natco_app/features/omr_processing/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_validation/data/repository/omr_validation_repository_impl.dart';
import 'package:natco_app/features/omr_validation/data/service/in_memory_omr_validation_data_source.dart';
import 'package:natco_app/features/sync/data/repository/sync_queue_repository_impl.dart';
import 'package:natco_app/features/sync/data/service/sync_queue_data_source.dart';
import 'package:natco_app/features/sync/domain/entity/sync_queue_entry.dart';
import 'package:natco_app/features/sync/domain/entity/sync_status.dart';
import 'package:natco_app/features/sync/domain/service/sync_conflict_policy.dart';
import 'package:natco_app/features/sync/domain/service/sync_reconciler.dart';
import '../../dummy_sync.dart';

final class _InMemoryQueueDataSource implements SyncQueueDataSource {
  final Map<String, SyncQueueEntry> _entries = <String, SyncQueueEntry>{};

  @override
  Future<Result<void>> enqueue(SyncQueueEntry entry) async {
    _entries[entry.syncId] = entry;
    return ok(null);
  }

  @override
  Future<Result<List<SyncQueueEntry>>> listQueue() async =>
      ok(_entries.values.toList());

  @override
  Future<Result<void>> updateEntry(SyncQueueEntry entry) async {
    _entries[entry.syncId] = entry;
    return ok(null);
  }

  @override
  Future<Result<void>> removeEntry(String syncId) async {
    _entries.remove(syncId);
    return ok(null);
  }
}

OmrSubmission _submission({
  required String omrId,
  required OmrProcessingStatus processingStatus,
}) => OmrSubmission(
  omrId: omrId,
  submissionId: 'sub_$omrId',
  sessionId: 'ses_1',
  assessmentId: 'as_1',
  schoolId: 'sch_1',
  clusterId: 'cl_1',
  districtId: 'di_1',
  stateId: 'st_1',
  capturedBy: 'demo_teacher',
  capturedAt: DateTime.utc(2026, 9, 15),
  deviceId: 'device_1',
  originalImagePath: '/device/omr/$omrId.jpg',
  imageQuality: const ImageQualityReport(
    blurScore: 0.9,
    brightnessScore: 0.8,
    contrastScore: 0.8,
    resolutionPx: 3000000,
    sheetDetected: true,
    markersDetected: 4,
    rotationDegrees: 0,
    perspectiveSkew: 0,
    verdict: QualityVerdict.pass,
  ),
  processingStatus: processingStatus,
  validationStatus: ValidationStatus.notRequired,
  createdAt: DateTime.utc(2026, 9, 15),
  updatedAt: DateTime.utc(2026, 9, 15),
);

void main() {
  late InMemoryOmrValidationDataSource omrDataSource;
  late OmrValidationRepositoryImpl omrRepository;
  late FakeFileSystemService fileSystem;
  late SyncQueueRepositoryImpl queueRepository;
  late SyncReconciler reconciler;

  setUp(() {
    fileSystem = FakeFileSystemService();
  });

  void buildWith(List<OmrSubmission> submissions) {
    omrDataSource = InMemoryOmrValidationDataSource(submissions: submissions);
    omrRepository = OmrValidationRepositoryImpl(
      fileSystem: fileSystem,
      syncQueue: DummySyncQueueRepository(),
      dataSource: omrDataSource,
      auditSink: InMemoryAuditSink(),
      idGenerator: const UuidIdGenerator(),
      clock: const SystemClock(),
      deviceInfo: const StaticDeviceInfoService(),
    );
    queueRepository = SyncQueueRepositoryImpl(
      dataSource: _InMemoryQueueDataSource(),
      conflictPolicy: const SyncConflictPolicy(),
      auditSink: InMemoryAuditSink(),
      idGenerator: const UuidIdGenerator(),
      clock: const SystemClock(),
      deviceInfo: const StaticDeviceInfoService(),
    );
    reconciler = SyncReconciler(
      queueRepository: queueRepository,
      omrRepository: omrRepository,
      fileSystem: fileSystem,
    );
  }

  group('stuck uploads', () {
    test('an entry stuck UPLOADING resets to PENDING', () async {
      buildWith(const <OmrSubmission>[]);
      await queueRepository.enqueue(
        SyncQueueEntry(
          syncId: 'sync_1',
          entityType: SyncEntityType.omrSubmission,
          entityId: 'sub_1',
          operation: SyncOperation.create,
          payloadRef: 'ref_1',
          idempotencyKey: 'idem_1',
          createdAt: DateTime.utc(2026),
          attemptCount: 1,
          status: SyncStatus.uploading,
        ),
      );

      await reconciler.reconcile();

      final List<SyncQueueEntry> queue =
          (await queueRepository.listQueue()).valueOrNull!;
      expect(queue.single.status, SyncStatus.pending);
    });
  });

  group('unfinished submissions', () {
    test(
      'a CAPTURED/PROCESSING submission whose image is on disk is left '
      'CAPTURED or reset to it',
      () async {
        buildWith(<OmrSubmission>[
          _submission(
            omrId: 'omr_captured',
            processingStatus: OmrProcessingStatus.captured,
          ),
          _submission(
            omrId: 'omr_processing',
            processingStatus: OmrProcessingStatus.processing,
          ),
        ]);
        fileSystem.addFile('/device/omr/omr_captured.jpg');
        fileSystem.addFile('/device/omr/omr_processing.jpg');

        await reconciler.reconcile();

        final OmrSubmission captured = (await omrRepository.getSubmission(
          'omr_captured',
        )).valueOrNull!;
        final OmrSubmission processing = (await omrRepository.getSubmission(
          'omr_processing',
        )).valueOrNull!;
        expect(captured.processingStatus, OmrProcessingStatus.captured);
        // Reset from a crash mid-run back to a clean, restartable state.
        expect(processing.processingStatus, OmrProcessingStatus.captured);
      },
    );

    test(
      'a submission whose image file is gone is marked evidence-missing, '
      'never silently dropped',
      () async {
        buildWith(<OmrSubmission>[
          _submission(
            omrId: 'omr_lost',
            processingStatus: OmrProcessingStatus.captured,
          ),
        ]);
        // Deliberately not added to fileSystem — the image is "gone".

        await reconciler.reconcile();

        final OmrSubmission result = (await omrRepository.getSubmission(
          'omr_lost',
        )).valueOrNull!;
        expect(
          result.processingStatus,
          OmrProcessingStatus.unreadableEvidenceMissing,
        );
      },
    );

    test('an already-scored submission is left untouched', () async {
      buildWith(<OmrSubmission>[
        _submission(omrId: 'omr_scored', processingStatus: OmrProcessingStatus.scored),
      ]);
      // No image on disk at all — if this submission were reconciled, it
      // would wrongly flip to evidence-missing.

      await reconciler.reconcile();

      final OmrSubmission result = (await omrRepository.getSubmission(
        'omr_scored',
      )).valueOrNull!;
      expect(result.processingStatus, OmrProcessingStatus.scored);
    });
  });
}
