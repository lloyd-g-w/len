import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:len/platform/camera_capture.dart';

/// A camera for tests: [takePhoto] waits until the test [answer]s (or
/// forever: Len "killed" meanwhile); [retrieveLost] hands out [lost] once.
class FakeCameraCapture implements CameraCapture {
  FakeCameraCapture({this.lost});

  /// The photo Android would hand back after killing Len.
  XFile? lost;

  /// How often [retrieveLost] was asked.
  int retrieved = 0;

  Completer<XFile?>? _shot;

  /// Whether the camera app is "in front".
  bool get open => _shot != null;

  @override
  bool get available => true;

  @override
  Future<XFile?> takePhoto() => (_shot = Completer<XFile?>()).future;

  /// The camera app returns [photo] (null: cancelled).
  void answer(XFile? photo) {
    final shot = _shot!;
    _shot = null;
    shot.complete(photo);
  }

  @override
  Future<XFile?> retrieveLost() async {
    retrieved++;
    final photo = lost;
    lost = null;
    return photo;
  }
}
