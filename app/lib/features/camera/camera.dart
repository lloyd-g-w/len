import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import '../../data/settings_repository.dart';
import '../../platform/camera_capture.dart';
import 'camera_purpose.dart';

/// A photo that came back after Len was killed while the camera app was
/// in front, and what the camera had been opened for (null if Len no
/// longer knows).
typedef LostPhoto = ({XFile photo, CameraPurpose? purpose});

/// The camera (Android), remembering what it was opened for.
///
/// Android may kill Len while the camera app is in front (low memory);
/// the photo then comes back only when Len starts again
/// ([CameraCapture.retrieveLost]). So [takePhoto] keeps its purpose in the
/// settings until the camera returns, and [retrieveLost] hands the photo
/// back with it, so the flow can carry on.
class Camera {
  Camera({
    required this._settings,
    required this._isClosed,
    this._capture = const SystemCameraCapture(),
  });

  final SettingsRepository _settings;

  /// Whether the database is closed (the app is going): nothing to keep.
  final bool Function() _isClosed;
  final CameraCapture _capture;
  bool _retrieved = false;
  int _taking = 0;

  /// Whether photos can be taken.
  bool get available => _capture.available;

  /// Takes a photo for [purpose] (null if cancelled); throws if the camera
  /// can't be opened.
  Future<XFile?> takePhoto(CameraPurpose purpose) async {
    _settings.cameraPurpose = purpose.encode();
    _taking++;
    try {
      return await _capture.takePhoto();
    } finally {
      // Len lived through it: nothing to recover. (The editor or screen
      // that asked may be gone, but then the user left it.)
      if (--_taking == 0 && !_isClosed()) _settings.cameraPurpose = null;
    }
  }

  /// The photo taken before Len was last killed, with its purpose; null
  /// if there is none. Asks once per run of the app: later calls (and
  /// any call while a photo is being taken) find nothing.
  Future<LostPhoto?> retrieveLost() async {
    if (_retrieved || _taking > 0) return null;
    _retrieved = true;
    final stored = _settings.cameraPurpose;
    XFile? photo;
    try {
      photo = await _capture.retrieveLost();
    } on Object catch (e) {
      debugPrint('Retrieving a lost photo failed: $e');
    }
    if (_isClosed()) return null;
    // Whatever came back, the purpose is settled (unless the user is
    // taking a new photo meanwhile).
    if (stored != null && _taking == 0) _settings.cameraPurpose = null;
    if (photo == null) return null;
    return (photo: photo, purpose: stored == null ? null : CameraPurpose.decode(stored));
  }
}
