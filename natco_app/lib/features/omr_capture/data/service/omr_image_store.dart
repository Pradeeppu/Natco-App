/// Durable local storage for captured OMR images.
///
/// "The captured JPEG is written to application documents storage before any
/// processing... Processing failures, crashes and low-memory kills therefore
/// never destroy the evidence" (docs/06-offline-sync-strategy.md §1). This is
/// the one piece of Phase 5 that has to be a real file write, not a Hive
/// value — an image is tens to hundreds of kilobytes, too large for a
/// `Box<String>` the way a JSON record is stored elsewhere in this app.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:natco_app/core/errors/failure.dart';
import 'package:natco_app/core/utils/result.dart';

abstract interface class OmrImageStore {
  /// Writes [bytes] durably and returns the local path they were written
  /// to. [submissionId] names the file — the app's own freshly-generated id,
  /// not the printed `omrId`: the printed id is operator-entered and has no
  /// uniqueness guarantee until Phase 6's duplicate registry exists, whereas
  /// `submissionId` cannot collide by construction.
  Future<Result<String>> writeOriginal({
    required String submissionId,
    required Uint8List bytes,
  });

  Future<Result<Uint8List>> read(String path);

  /// Whether a file exists at [path]. Used by recovery/reconciliation code
  /// that must tell "missing evidence" apart from every other failure mode
  /// (docs/06-offline-sync-strategy.md §4, point 4).
  Future<bool> exists(String path);
}

/// Writes into a directory resolved lazily by [rootDirectory] — a real
/// device resolves this to `getApplicationDocumentsDirectory()` from
/// `path_provider`; a test resolves it to a temp directory it controls, with
/// no platform channel involved either way.
final class FileSystemOmrImageStore implements OmrImageStore {
  FileSystemOmrImageStore({required Future<Directory> Function() rootDirectory})
    : _rootDirectory = rootDirectory;

  final Future<Directory> Function() _rootDirectory;

  static const String _subdirectory = 'omr_originals';

  @override
  Future<Result<String>> writeOriginal({
    required String submissionId,
    required Uint8List bytes,
  }) => guardAsync(() async {
    final Directory dir = await _capturesDirectory();
    final File file = File('${dir.path}/$submissionId.jpg');
    // Write-then-rename would be the fully crash-safe form of this, but a
    // torn write here is already the least damaging failure this pipeline
    // has: the quality gate that runs immediately after treats an unreadable
    // file exactly like a bad photo (Step 1 of docs/07-omr-pipeline.md), and
    // no submission record is created before this write completes, so there
    // is nothing yet claiming this file is good.
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }, onError: _mapError);

  @override
  Future<Result<Uint8List>> read(String path) => guardAsync(
    () => File(path).readAsBytes(),
    onError: _mapError,
  );

  @override
  Future<bool> exists(String path) async => File(path).existsSync();

  Future<Directory> _capturesDirectory() async {
    final Directory root = await _rootDirectory();
    final Directory dir = Directory('${root.path}/$_subdirectory');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Failure _mapError(Object error, StackTrace stackTrace) =>
      StorageFailure.localWrite(
        diagnostic: 'omr image store: $error',
        cause: error,
      );
}
