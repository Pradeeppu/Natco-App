/// Abstract interface for file system operations, allowing domain code to check
/// files without importing `dart:io`.
library;

import 'dart:io';

abstract interface class FileSystemService {
  /// Checks if a file exists at the given [path].
  bool fileExistsSync(String path);
}

/// Real implementation using `dart:io`.
final class PlatformFileSystemService implements FileSystemService {
  const PlatformFileSystemService();

  @override
  bool fileExistsSync(String path) => File(path).existsSync();
}

/// Fake implementation for tests.
final class FakeFileSystemService implements FileSystemService {
  FakeFileSystemService({List<String>? existingFiles})
      : _existingFiles = Set<String>.from(existingFiles ?? <String>[]);

  final Set<String> _existingFiles;

  @override
  bool fileExistsSync(String path) => _existingFiles.contains(path);

  void addFile(String path) {
    _existingFiles.add(path);
  }

  void removeFile(String path) {
    _existingFiles.remove(path);
  }
}
