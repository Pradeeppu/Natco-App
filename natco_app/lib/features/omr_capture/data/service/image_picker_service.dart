/// Abstracts image selection behind an interface, the same reason
/// `AuthService` and `ConnectivityService` are interfaces: `image_picker`
/// talks to a platform channel, which a widget test cannot drive, and the
/// capture flow itself has nothing to do with which source produced the
/// bytes.
library;

import 'dart:typed_data';

import 'package:image_picker/image_picker.dart' as picker;

abstract interface class ImagePickerService {
  /// Opens the camera. Returns `null` if the user cancels.
  Future<Uint8List?> captureFromCamera();

  /// Opens the gallery/file picker. Returns `null` if the user cancels.
  Future<Uint8List?> pickFromGallery();
}

/// Wraps `package:image_picker`.
final class PlatformImagePickerService implements ImagePickerService {
  PlatformImagePickerService([picker.ImagePicker? imagePicker])
    : _picker = imagePicker ?? picker.ImagePicker();

  final picker.ImagePicker _picker;

  @override
  Future<Uint8List?> captureFromCamera() async {
    final picker.XFile? file = await _picker.pickImage(
      source: picker.ImageSource.camera,
    );
    return file?.readAsBytes();
  }

  @override
  Future<Uint8List?> pickFromGallery() async {
    final picker.XFile? file = await _picker.pickImage(
      source: picker.ImageSource.gallery,
    );
    return file?.readAsBytes();
  }
}
