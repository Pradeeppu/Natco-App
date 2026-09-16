/// Tests for [FirebaseOmrDriveBackupService] and [FakeOmrDriveBackupService].
///
/// The real service's only logic is: base64-encode the file, call the
/// injected invoker, and turn its result (or a thrown exception) into a
/// plain `bool` — everything Drive-specific now lives server-side, in
/// `firebase/functions/src/driveBackup.ts`, which has its own Jest tests.
/// `FirebaseFunctions.instance` itself isn't fakeable, so the invocation is
/// injected here exactly the way the old client-side Drive logic injected
/// `DriveFilesApi` earlier this session.
library;

import 'dart:convert';
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

  group('FirebaseOmrDriveBackupService', () {
    test('encodes the file and returns true when the function reports success', () async {
      Map<String, Object?>? sentData;
      final FirebaseOmrDriveBackupService service = FirebaseOmrDriveBackupService(
        invoke: (Map<String, Object?> data) async {
          sentData = data;
          return <String, Object?>{'success': true};
        },
      );

      final bool result = await service.backup(
        file: file,
        folderName: 'OMR_Captures_as_demo',
        fileName: 'sheet.jpg',
      );

      expect(result, isTrue);
      expect(sentData?['folderName'], 'OMR_Captures_as_demo');
      expect(sentData?['fileName'], 'sheet.jpg');
      expect(sentData?['imageBase64'], base64Encode(<int>[1, 2, 3, 4, 5]));
    });

    test('returns false when the function reports failure', () async {
      final FirebaseOmrDriveBackupService service = FirebaseOmrDriveBackupService(
        invoke: (_) async => <String, Object?>{'success': false},
      );

      final bool result = await service.backup(
        file: file,
        folderName: 'OMR_Captures_as_demo',
        fileName: 'sheet.jpg',
      );

      expect(result, isFalse);
    });

    test('a thrown exception is reported as false, never rethrown', () async {
      final FirebaseOmrDriveBackupService service = FirebaseOmrDriveBackupService(
        invoke: (_) async => throw Exception('offline'),
      );

      final bool result = await service.backup(
        file: file,
        folderName: 'OMR_Captures_as_demo',
        fileName: 'sheet.jpg',
      );

      expect(
        result,
        isFalse,
        reason:
            'the capture flow treats this as fire-and-forget best-effort '
            'backup — it must never surface as an unhandled exception',
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
