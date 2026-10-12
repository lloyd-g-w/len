/// Whether the primary pointer is coarse (a finger), from the browser's
/// `(pointer: coarse)` media query on the web; false on native platforms,
/// where the platform itself decides (see `Targets.touchFirst`).
library;

export 'coarse_pointer_native.dart' if (dart.library.js_interop) 'coarse_pointer_web.dart';
