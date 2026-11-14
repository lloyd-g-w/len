/// Where a browser sign-in's answer reaches Len on a desktop
/// (`startSigninListener`): a listener on `http://127.0.0.1:PORT/callback`
/// that the server's sign-in page redirects to (RFC 8252's loopback
/// redirect, sync/browser_signin.dart). None in a browser.
library;

export 'signin_listener_native.dart' if (dart.library.js_interop) 'signin_listener_web.dart';
