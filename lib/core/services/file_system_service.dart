/// Abstract interface for file system operations, allowing domain code to
/// check and write files without importing `dart:io` directly.
library;

import 'dart:io';
import 'dart:typed_data';

abstract interface class FileSystemService {
  /// Checks if a file exists at the given [path].
  bool fileExistsSync(String path);

  /// Writes [bytes] to [path], creating parent directories as needed, and
  /// does not return until the write is durable on disk.
  ///
  /// This is what Critical Rule 12 ("kill mid-capture loses nothing") rests
  /// on for a captured OMR image: the bytes must be safely on disk before
  /// this call returns, not merely handed to a buffer that a kill a moment
  /// later could still lose.
  Future<void> writeBytes(String path, Uint8List bytes);
}

/// Real implementation using `dart:io`.
final class PlatformFileSystemService implements FileSystemService {
  const PlatformFileSystemService();

  @override
  bool fileExistsSync(String path) => File(path).existsSync();

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    final File file = File(path);
    await file.parent.create(recursive: true);
    // `flush: true` forces the write to disk before completing, rather than
    // returning as soon as the OS buffer accepts it — the difference between
    // "durable" and "probably fine".
    await file.writeAsBytes(bytes, flush: true);
  }
}

/// Fake implementation for tests.
final class FakeFileSystemService implements FileSystemService {
  FakeFileSystemService({List<String>? existingFiles})
      : _existingFiles = Set<String>.from(existingFiles ?? <String>[]);

  final Set<String> _existingFiles;
  final Map<String, Uint8List> _writtenBytes = <String, Uint8List>{};

  @override
  bool fileExistsSync(String path) => _existingFiles.contains(path);

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    _writtenBytes[path] = bytes;
    _existingFiles.add(path);
  }

  /// What a test asserts against — the bytes as this fake actually received
  /// them, not merely that a write was attempted.
  Uint8List? bytesWrittenTo(String path) => _writtenBytes[path];

  void addFile(String path) {
    _existingFiles.add(path);
  }

  void removeFile(String path) {
    _existingFiles.remove(path);
  }
}
