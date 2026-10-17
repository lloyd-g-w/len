/// Opens a live connection (`connectLive`): natively with the access token
/// in a header; in a browser, which cannot set headers on a WebSocket, with
/// a one-time ticket asked for first (the token never goes into a URL).
library;

export 'live_socket_native.dart' if (dart.library.js_interop) 'live_socket_web.dart';
