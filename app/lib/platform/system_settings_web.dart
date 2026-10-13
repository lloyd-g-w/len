import 'package:flutter/foundation.dart';

/// Overrides [canOpenMicrophoneSettings] in tests.
@visibleForTesting
bool? debugCanOpenMicrophoneSettings;

/// Browsers keep the microphone permission in their own site settings,
/// which a page can't open.
bool get canOpenMicrophoneSettings => debugCanOpenMicrophoneSettings ?? false;

/// Not available in browsers.
Future<bool> openMicrophoneSettings() async => false;
