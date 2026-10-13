/// Opening the system's settings for Len, to allow the microphone after it
/// was refused: Len's app page on Android (`RecordingServicePlugin.kt`),
/// the microphone privacy page on Windows. Elsewhere (Linux, the web) there
/// is no such page, and [canOpenMicrophoneSettings] is false.
library;

export 'system_settings_native.dart' if (dart.library.js_interop) 'system_settings_web.dart';
