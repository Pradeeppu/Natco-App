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
///
/// NOTE: Drive backup requires Cloud Functions, which in turn requires the
/// Firebase Blaze (pay-as-you-go) plan. On the Spark free plan the
/// [NoOpOmrDriveBackupService] is wired instead — it returns `false` on every
/// call, which is the documented "best-effort" failure contract. No data is
/// lost: the sheet is already stored durably in Hive and synced to Firestore
/// via the normal sync queue. To enable real Drive backup, upgrade the project
/// to Blaze, deploy `firebase/functions/`, and swap the wiring in
/// `service_locator.dart` to a `FirebaseOmrDriveBackupService` implementation.
library;

import 'dart:io';

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

/// No-op implementation used when Cloud Functions are not available (Spark
/// free plan). Returns `false` so callers know the backup did not run, but
/// never throws — consistent with the best-effort contract of the interface.
final class NoOpOmrDriveBackupService implements OmrDriveBackupService {
  const NoOpOmrDriveBackupService();

  @override
  Future<bool> backup({
    required File file,
    required String folderName,
    required String fileName,
  }) async => false;
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
