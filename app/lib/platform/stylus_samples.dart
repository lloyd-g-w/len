/// Dense stylus input (`openStylusSamples`): on Android, the historical
/// `MotionEvent` samples Flutter drops arrive over a binary channel from
/// `MainActivity`; elsewhere there is nothing to add (null).
library;

export 'stylus_samples_native.dart' if (dart.library.js_interop) 'stylus_samples_web.dart';
