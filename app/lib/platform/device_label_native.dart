import 'dart:io';

import 'package:flutter/services.dart';

const MethodChannel _device = MethodChannel('len/device');

/// The platform, with the host name on computers: `Linux (studio)`,
/// `Windows (DESKTOP-4F2)`; `Android` alone (its name comes from
/// [systemDeviceName]).
String get platformDeviceName {
  final platform = Platform.isAndroid
      ? 'Android'
      : Platform.isIOS
      ? 'iPad'
      : Platform.isLinux
      ? 'Linux'
      : Platform.isMacOS
      ? 'Mac'
      : Platform.isWindows
      ? 'Windows'
      : 'Device';
  if (Platform.isAndroid || Platform.isIOS) return platform;
  final String host;
  try {
    host = Platform.localHostname.split('.').first.trim();
  } on Object {
    return platform;
  }
  return host.isEmpty || host == 'localhost' ? platform : '$platform ($host)';
}

/// The name the system gives the device, where it has one: Android's
/// device name (Settings → About, "Galaxy Tab S9"), else its maker and
/// model (`MainActivity.kt`). Null elsewhere, or when it can't be had.
Future<String?> systemDeviceName() async {
  if (!Platform.isAndroid) return null;
  try {
    final name = (await _device.invokeMethod<String>('name'))?.trim();
    return name == null || name.isEmpty ? null : name;
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
