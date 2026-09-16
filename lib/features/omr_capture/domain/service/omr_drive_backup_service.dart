/// Backs up a captured OMR image to a shared Google Drive folder, so a sheet
/// already durable on-device (Critical Rule 12) also has an off-device copy
/// the moment connectivity allows it.
///
/// Deliberately **not** a per-user Google sign-in: the Drive credential is
/// provisioned once by a super admin and lives only in the Cloud Function's
/// secrets, never on a device. Every capturer still just signs into this app
/// the normal way (Firebase Auth) — nothing Google-branded ever reaches
/// them. See `docs/13-google-drive-backup-setup.md` for how that Cloud
/// Function (`backupOmrCapture`, in `firebase/functions/`) is provisioned;
/// none of that exists in this repository, since it's per-deployment
/// configuration, not code.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';

abstract interface class OmrDriveBackupService {
  /// Best-effort: returns `false` on any failure rather than throwing, since
  /// the caller treats this as a fire-and-forget convenience copy, never the
  /// system of record.
  Future<bool> backup({
    required File file,
    required String folderName,
    required String fileName,
  });
}

/// Calls the `backupOmrCapture` Cloud Function.
final class FirebaseOmrDriveBackupService implements OmrDriveBackupService {
  FirebaseOmrDriveBackupService({
    Future<Object?> Function(Map<String, Object?> data)? invoke,
  }) : _invoke = invoke ?? _defaultInvoke;

  /// The actual call, injected so `omr_drive_backup_service_test.dart` can
  /// swap in a fake — `FirebaseFunctions.instance` itself isn't fakeable,
  /// and `HttpsCallableResult` has no public constructor a fake could return
  /// either, hence returning the decoded `.data` directly rather than the
  /// wrapper.
  final Future<Object?> Function(Map<String, Object?> data) _invoke;

  static Future<Object?> _defaultInvoke(Map<String, Object?> data) async {
    final HttpsCallableResult<Object?> result = await FirebaseFunctions
        .instance
        .httpsCallable('backupOmrCapture')
        .call<Object?>(data);
    return result.data;
  }

  @override
  Future<bool> backup({
    required File file,
    required String folderName,
    required String fileName,
  }) async {
    try {
      final Uint8List bytes = await file.readAsBytes();
      final Object? data = await _invoke(<String, Object?>{
        'folderName': folderName,
        'fileName': fileName,
        'imageBase64': base64Encode(bytes),
      });
      return data is Map && data['success'] == true;
    } catch (e) {
      return false;
    }
  }
}

/// Demo/test implementation: simulates a working backup with no network
/// call, matching how every other demo data source in this app behaves
/// rather than silently doing nothing.
final class FakeOmrDriveBackupService implements OmrDriveBackupService {
  const FakeOmrDriveBackupService();

  @override
  Future<bool> backup({
    required File file,
    required String folderName,
    required String fileName,
  }) async => true;
}
