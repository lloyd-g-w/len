import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const MethodChannel _recording = MethodChannel('len/recording_service');

/// Overrides [canOpenMicrophoneSettings] in tests.
@visibleForTesting
bool? debugCanOpenMicrophoneSettings;

/// Whether [openMicrophoneSettings] can open a page (Android, Windows).
bool get canOpenMicrophoneSettings =>
    debugCanOpenMicrophoneSettings ?? (Platform.isAndroid || Platform.isWindows);

/// Opens where the microphone is allowed for Len; false if it couldn't.
Future<bool> openMicrophoneSettings() async {
  try {
    if (Platform.isAndroid) {
      return await _recording.invokeMethod<bool>('openAppSettings') ?? false;
    }
    if (Platform.isWindows) return await launchUrl(Uri.parse('ms-settings:privacy-microphone'));
  } on MissingPluginException {
    // Tests, or a runner without the channel.
  } on PlatformException catch (e) {
    debugPrint('System settings unavailable: $e');
  }
  return false;
}
