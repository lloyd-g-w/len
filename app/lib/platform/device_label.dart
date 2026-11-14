/// What a device is called before the user names it (`DeviceName`): the
/// platform and, where known, the computer's host name or the browser.
library;

export 'device_label_native.dart' if (dart.library.js_interop) 'device_label_web.dart';
