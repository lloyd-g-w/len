/// Files for audio recording and playback (`newCaptureTarget`,
/// `deleteCapture`, `openCaptureSink`, `recordingUnavailableReason`, `audioUriFor`,
/// `releaseAudioUri`): temporary files and blob paths natively, blob URLs
/// in browsers.
library;

export 'audio_files_native.dart' if (dart.library.js_interop) 'audio_files_web.dart';
