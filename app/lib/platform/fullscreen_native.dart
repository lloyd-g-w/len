import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Served by the Linux (`window_state.cc`) and Windows (`flutter_window.cpp`)
/// runners.
const MethodChannel _window = MethodChannel('len/window');

/// Puts the desktop window into full screen or back. Returns whether full
/// screen was requested (false on Android, which uses immersive mode).
Future<bool> setFullscreen(bool on) async {
  if (!Platform.isLinux && !Platform.isWindows) return false;
  try {
    return await _window.invokeMethod<bool>('setFullScreen', on) ?? false;
  } on MissingPluginException {
    return false; // Tests, or a runner without the channel.
  } on PlatformException catch (e) {
    debugPrint('Full screen unavailable: $e');
    return false;
  }
}
