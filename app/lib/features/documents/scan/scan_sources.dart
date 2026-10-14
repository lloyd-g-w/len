import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' as picker;

import '../../editor/images/image_import.dart';

/// Where the photos of a scan come from: image files (every platform) and,
/// on Android, the camera. Tests pass their own.
class ScanSources {
  const ScanSources({this.pick, this.camera});

  /// Picks photos instead of the file picker.
  final Future<List<XFile>> Function()? pick;

  /// Takes a photo instead of the system camera (and offers it anywhere).
  final Future<XFile?> Function()? camera;

  /// The platform's: the file picker, and the camera on Android.
  static const ScanSources system = ScanSources();

  /// What the scan flows use when not told (tests set their own).
  @visibleForTesting
  static ScanSources? debugSources;

  /// [debugSources], else [system].
  static ScanSources get current => debugSources ?? system;

  /// Whether photos can be taken ([takePhoto]).
  bool get hasCamera =>
      camera != null || (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static const _types = [
    XTypeGroup(label: 'Images', extensions: ImageImport.extensions, mimeTypes: ['image/*']),
  ];

  /// Lets the user pick photos (none if cancelled).
  Future<List<XFile>> pickPhotos() => pick?.call() ?? openFiles(acceptedTypeGroups: _types);

  /// Takes a photo with the camera (null if cancelled); throws if the
  /// camera can't be opened.
  Future<XFile?> takePhoto() =>
      camera?.call() ?? picker.ImagePicker().pickImage(source: picker.ImageSource.camera);
}
