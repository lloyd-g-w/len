/// Graceful shutdown: finishing requests in flight before the store closes.
library;

import 'dart:async';

import 'package:shelf/shelf.dart';

/// Counts requests whose handlers are still running, so shutdown can wait
/// for them before closing the database under their feet.
class RequestTracker {
  var _inFlight = 0;
  Completer<void>? _idle;

  /// Number of requests currently being handled.
  int get inFlight => _inFlight;

  /// Middleware counting every request until its handler has returned (a
  /// streamed response body, such as a blob download, is not waited for:
  /// it no longer touches the database).
  Middleware get middleware => (Handler inner) {
    return (Request request) async {
      _inFlight++;
      try {
        return await inner(request);
      } finally {
        if (--_inFlight == 0) {
          _idle?.complete();
          _idle = null;
        }
      }
    };
  };

  /// Completes with `true` once no request is in flight, or with `false`
  /// when [timeout] passes first.
  Future<bool> drain(Duration timeout) async {
    if (_inFlight == 0) return true;
    final idle = _idle ??= Completer<void>();
    return idle.future.then((_) => true).timeout(timeout, onTimeout: () => false);
  }
}
