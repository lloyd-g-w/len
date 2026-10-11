/// Full screen for presentation mode (`setFullscreen`): the browser's
/// fullscreen API on the web; elsewhere the editor's immersive mode hides
/// the system bars (Android), and desktop windows stay as they are (no
/// window plugin; maximise the window with the window manager).
library;

export 'fullscreen_native.dart' if (dart.library.js_interop) 'fullscreen_web.dart';
