/// The device's physical memory in bytes, or null when unknown (the web,
/// or the platform wouldn't say). Read once; for sizing caches.
library;

export 'physical_memory_native.dart' if (dart.library.js_interop) 'physical_memory_web.dart';
