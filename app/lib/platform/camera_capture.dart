import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:image_picker/image_picker.dart' as picker;

/// Taking photos with the system's camera app, and getting back one taken
/// while Android killed Len. Tests pass fakes.
abstract interface class CameraCapture {
  /// Whether there is a camera to offer.
  bool get available;

  /// Takes a photo (null if cancelled); throws if the camera can't open.
  Future<XFile?> takePhoto();

  /// The photo taken in a camera app opened before Len was last killed,
  /// once (null if there is none).
  Future<XFile?> retrieveLost();
}

/// The camera through `image_picker`: Android only (no camera anywhere
/// else; nothing to retrieve there either).
class SystemCameraCapture implements CameraCapture {
  const SystemCameraCapture();

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  bool get available => _android;

  @override
  Future<XFile?> takePhoto() => picker.ImagePicker().pickImage(source: picker.ImageSource.camera);

  @override
  Future<XFile?> retrieveLost() async {
    if (!_android) return null;
    final picker.LostDataResponse lost;
    try {
      lost = await picker.ImagePicker().retrieveLostData();
    } on MissingPluginException {
      return null; // No plugin (tests).
    }
    if (lost.isEmpty) return null;
    if (lost.exception case final e?) debugPrint('Camera failed before Len was closed: $e');
    return lost.file;
  }
}
