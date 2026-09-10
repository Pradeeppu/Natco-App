/// The real "kill-during-capture loses nothing" proof
/// (docs/08-mvp-implementation-plan.md Phase 5 exit criteria).
///
/// Two things have to be true, proven directly rather than by code
/// inspection:
///
/// 1. The captured image is durably on disk the moment it is picked — even
///    if the app is killed before an `OmrSubmission` record is ever
///    created, the photo itself is not lost.
/// 2. Once a submission record *is* created, it survives a real close and
///    reopen of Hive, the same proof `hive_persistence_test.dart` uses for
///    sessions in Phase 4.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:natco_app/core/services/logger.dart';
import 'package:natco_app/core/utils/clock.dart';
import 'package:natco_app/features/omr_capture/data/repository/hive_omr_submissions_repository.dart';
import 'package:natco_app/features/omr_capture/data/service/omr_image_store.dart';
import 'package:natco_app/features/omr_capture/domain/entity/image_quality_report.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_processing_status.dart';
import 'package:natco_app/features/omr_capture/domain/entity/omr_submission.dart';
import 'package:natco_app/features/omr_capture/domain/entity/validation_status.dart';

void main() {
  group('image durability', () {
    late Directory tempDir;
    late FileSystemOmrImageStore store;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('natco_omr_image_test_');
      store = FileSystemOmrImageStore(rootDirectory: () async => tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('a written image is durably readable back, byte for byte', () async {
      final Uint8List bytes = Uint8List.fromList(
        List<int>.generate(1000, (int i) => i % 256),
      );
      final writeResult = await store.writeOriginal(
        submissionId: 'sub-1',
        bytes: bytes,
      );
      expect(writeResult.isSuccess, isTrue);
      final String path = writeResult.valueOrNull!;

      expect(await store.exists(path), isTrue);
      final readResult = await store.read(path);
      expect(readResult.valueOrNull, bytes);
    });

    test('the image survives even if no submission record is ever created', () async {
      // This is the crash scenario itself: the app captures a photo, writes
      // it durably, and is killed before it ever gets to create the
      // OmrSubmission record that would reference it. No submission is
      // created in this test at all — the assertion is that the file is
      // still there anyway.
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      final writeResult = await store.writeOriginal(
        submissionId: 'orphaned-sub',
        bytes: bytes,
      );
      final String path = writeResult.valueOrNull!;

      // Simulate the process dying right here — nothing further happens on
      // this store instance, and a fresh one (pointed at the same directory,
      // the way a relaunched app would be) still finds the file.
      final FileSystemOmrImageStore afterRestart = FileSystemOmrImageStore(
        rootDirectory: () async => tempDir,
      );
      expect(await afterRestart.exists(path), isTrue);
      final readResult = await afterRestart.read(path);
      expect(readResult.valueOrNull, bytes);
    });

    test('writing two submissions never collides on the same file', () async {
      final resultA = await store.writeOriginal(
        submissionId: 'sub-a',
        bytes: Uint8List.fromList(<int>[1]),
      );
      final resultB = await store.writeOriginal(
        submissionId: 'sub-b',
        bytes: Uint8List.fromList(<int>[2]),
      );
      expect(resultA.valueOrNull, isNot(resultB.valueOrNull));
      expect((await store.read(resultA.valueOrNull!)).valueOrNull, <int>[1]);
      expect((await store.read(resultB.valueOrNull!)).valueOrNull, <int>[2]);
    });
  });

  group('submission record durability', () {
    late Directory tempDir;
    final Clock clock = FixedClock(DateTime.utc(2026, 9, 11, 9));
    final AppLogger logger = AppLogger(minimumLevel: LogLevel.error, sinks: const []);

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('natco_omr_hive_test_');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('a created submission survives closing and reopening the Hive box', () async {
      final HiveOmrSubmissionsRepository beforeRestart =
          HiveOmrSubmissionsRepository(hive: Hive, clock: clock, logger: logger);

      const ImageQualityReport report = ImageQualityReport(
        blurScore: 0.9,
        brightnessScore: 0.5,
        contrastScore: 0.5,
        shadowDeviation: 0.05,
        verdict: ImageQualityVerdict.pass,
        failureReasons: <String>[],
      );
      final DateTime now = clock.nowUtc();
      final OmrSubmission submission = OmrSubmission(
        submissionId: 'sub-1',
        omrId: '0001827',
        sessionId: 'session-1',
        assessmentId: 'assessment-1',
        studentId: 'student-1',
        schoolId: 'school-1',
        clusterId: 'cluster-1',
        districtId: 'district-1',
        stateId: 'state-1',
        capturedBy: 'teacher-1',
        capturedAt: now,
        deviceId: 'device-1',
        originalImagePath: '/data/omr_originals/sub-1.jpg',
        imageQuality: report,
        processingStatus: OmrProcessingStatus.qualityChecked,
        validationStatus: ValidationStatus.notRequired,
        createdAt: now,
        updatedAt: now,
      );
      await beforeRestart.createSubmission(submission);

      await Hive.close();

      final HiveOmrSubmissionsRepository afterRestart =
          HiveOmrSubmissionsRepository(hive: Hive, clock: clock, logger: logger);
      final recovered = await afterRestart.getSubmission('sub-1');
      expect(recovered.valueOrNull?.omrId, '0001827');
      expect(
        recovered.valueOrNull?.originalImagePath,
        '/data/omr_originals/sub-1.jpg',
      );
      expect(recovered.valueOrNull?.processingStatus, OmrProcessingStatus.qualityChecked);

      final forSession = await afterRestart.listForSession('session-1');
      expect(forSession.valueOrNull, hasLength(1));
    });
  });
}
