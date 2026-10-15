import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../../camera/camera.dart';
import '../../camera/camera_purpose.dart';
import '../../editor/images/image_import.dart';

/// Where the photos of a scan come from: image files (every platform) and,
/// on Android, the app's [Camera]. Tests pass their own.
class ScanSources {
  const ScanSources({this.pick, this.camera});

  /// Picks photos instead of the file picker.
  final Future<List<XFile>> Function()? pick;

  /// Takes a photo instead of the system camera (and offers it anywhere).
  final Future<XFile?> Function()? camera;

  /// The platform's: the file picker, and the app's camera.
  static const ScanSources system = ScanSources();

  /// What the scan flows use when not told (tests set their own).
  @visibleForTesting
  static ScanSources? debugSources;

  /// [debugSources], else [system].
  static ScanSources get current => debugSources ?? system;

  /// Whether photos can be taken ([takePhoto]), [system] being the app's
  /// camera (none without an `AppScope`).
  bool hasCamera(Camera? system) => camera != null || (system?.available ?? false);

  static const _types = [
    XTypeGroup(label: 'Images', extensions: ImageImport.extensions, mimeTypes: ['image/*']),
  ];

  /// Lets the user pick photos (none if cancelled).
  Future<List<XFile>> pickPhotos() => pick?.call() ?? openFiles(acceptedTypeGroups: _types);

  /// Takes a photo for [purpose] with the camera (null if cancelled);
  /// throws if the camera can't be opened.
  Future<XFile?> takePhoto(Camera? system, CameraPurpose purpose) =>
      camera?.call() ?? (system ?? (throw StateError('No camera'))).takePhoto(purpose);
}
