/// The browser's storage for Len's data (`browserStorage`): whether it is
/// *persistent* (browsers may otherwise evict IndexedDB under storage
/// pressure) and how much of the quota is used. Native platforms keep data
/// in files and have none (`browserStorage` is null).
library;

export 'browser_storage_native.dart' if (dart.library.js_interop) 'browser_storage_web.dart';
