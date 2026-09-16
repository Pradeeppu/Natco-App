/// Tests for [NoOpOmrDriveBackupService] and [FakeOmrDriveBackupService].
///
/// `FirebaseOmrDriveBackupService` (which called the `backupOmrCapture`
/// Cloud Function — still built and tested independently in
/// `firebase/functions/src/driveBackup.test.ts`) is not wired into
/// `service_locator.dart` for now: Cloud Functions require the Firebase
/// Blaze plan, and this project defaults to the free Spark plan until
/// someone deliberately upgrades. `NoOpOmrDriveBackupService` is what real
/// (non-demo) environments get instead — see
/// `omr_drive_backup_service.dart`'s doc comment.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:natco_app/features/omr_capture/domain/service/omr_drive_backup_service.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory tempDir;
  late File file;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('drive_backup_test');
    file = File(path.join(tempDir.path, 'sheet.jpg'));
    await file.writeAsBytes(<int>[1, 2, 3, 4, 5]);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('NoOpOmrDriveBackupService', () {
    test('always reports false, without throwing or touching the network', () async {
      const NoOpOmrDriveBackupService service = NoOpOmrDriveBackupService();

      final bool result = await service.backup(
        file: file,
        folderName: 'OMR_Captures_as_demo',
        fileName: 'sheet.jpg',
      );

      expect(
        result,
        isFalse,
        reason:
            'the caller must be able to tell the backup did not run — a '
            'silent true would be a lie about what actually happened',
      );
    });
  });

  group('FakeOmrDriveBackupService', () {
    test('simulates a working backup with no network call', () async {
      const FakeOmrDriveBackupService service = FakeOmrDriveBackupService();

      final bool result = await service.backup(
        file: file,
        folderName: 'OMR_Captures_as_demo',
        fileName: 'sheet.jpg',
      );

      expect(result, isTrue);
    });
  });
}
