/// The system's media controls for playing recordings
/// (`systemMediaControls`, types in `media_controls_api.dart`): Android's
/// media session in a foreground service, MPRIS on Linux, the Media
/// Session API in browsers; none on Windows (media keys reach the open
/// editor as key events, see `playback_keys.dart`).
library;

export 'media_controls_api.dart';
export 'media_controls_native.dart' if (dart.library.js_interop) 'media_controls_web.dart';
