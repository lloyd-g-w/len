import 'package:web/web.dart' as web;

import '../core/browser_names.dart';

/// The browser and its system, from the user agent: `Firefox on Linux`,
/// `Chrome on Android`, `Safari on iPad`; `Browser` when unknown.
String get platformDeviceName => browserDeviceName(web.window.navigator.userAgent);

/// Browsers give no device name.
Future<String?> systemDeviceName() async => null;
