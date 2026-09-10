/// Durable capture: the image is on disk before anything else touches it
/// (docs/08-mvp-implementation-plan.md, phase 5 exit criteria; Critical
/// Rule 12).
///
/// Deliberately takes [documentsRootPath] as a parameter rather than calling
/// `path_provider` itself: resolving the real app-documents directory needs a
/// platform channel, which — like camera access — cannot be verified without
/// a device in this environment. Everything from "here is the root
/// directory" onward is pure Dart and fully tested; the one line a real
/// caller adds is `(await getApplicationDocumentsDirectory()).path`.
library;

import 'dart:typed_data';

import 'package:natco_app/core/constants/collections.dart';
import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/services/file_system_service.dart';
import 'package:natco_app/core/utils/result.dart';
import 'package:path/path.dart' as p;

abstract final class OmrImageWriter {
  /// Writes [imageBytes] under [documentsRootPath], at the path
  /// `StoragePaths.omrOriginal` already defines — the same path shape the
  /// eventual Storage upload uses, so nothing has to be renamed on sync.
  ///
  /// Returns the absolute path on success. A failure here must never lose
  /// the bytes silently: the caller still holds [imageBytes] and the
  /// in-memory submission record it came from, so a failed write is
  /// something the capture flow can retry, not something that discards
  /// evidence.
  static Future<Result<String>> writeCapturedImage({
    required FileSystemService fileSystem,
    required String documentsRootPath,
    required Uint8List imageBytes,
    required String academicYear,
    required String assessmentId,
    required String stateId,
    required String districtId,
    required String clusterId,
    required String schoolId,
    required DateTime capturedAt,
    required String omrId,
  }) async {
    final String relativePath = StoragePaths.omrOriginal(
      academicYear: academicYear,
      assessmentId: assessmentId,
      stateId: stateId,
      districtId: districtId,
      clusterId: clusterId,
      schoolId: schoolId,
      date: _dateOnly(capturedAt),
      omrId: omrId,
    );
    final String absolutePath = p.join(documentsRootPath, relativePath);

    return guardAsync(() async {
      await fileSystem.writeBytes(absolutePath, imageBytes);
      return absolutePath;
    }, onError: (Object error, StackTrace stackTrace) => StorageFailure.localWrite(
      diagnostic: 'failed to write captured image: $error',
      cause: error,
    ));
  }

  /// `YYYY-MM-DD`, UTC — the storage path groups sheets by capture day, and
  /// mixing local and UTC dates here would put the same evening's sheets in
  /// two different folders depending on which side of midnight a device's
  /// clock read.
  static String _dateOnly(DateTime dateTime) {
    final DateTime utc = dateTime.toUtc();
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}-${twoDigits(utc.month)}-${twoDigits(utc.day)}';
  }
}
