/// The directory the app keeps its data in (`appDataDirectory`): the
/// platform's application-support directory natively; browsers have none
/// (data lives in IndexedDB), so the web returns an empty string.
library;

export 'app_directory_native.dart' if (dart.library.js_interop) 'app_directory_web.dart';
