/// Full screen for presentation mode (`setFullscreen`): the browser's
/// fullscreen API on the web; the window itself on Linux and Windows (the
/// runners' `len/window` channel); on Android the editor's immersive mode
/// hides the system bars instead.
library;

export 'fullscreen_native.dart' if (dart.library.js_interop) 'fullscreen_web.dart';
