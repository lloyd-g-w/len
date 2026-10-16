import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'sync_api.dart';

/// Keeps one connection to the server's event stream (`/v1/events`) open
/// while [run] is on, reconnecting with backoff, and hands its events to
/// [onEvent].
///
/// A connection that has said nothing for [silence] (the server sends a
/// heartbeat every 20 s) is taken for dead and replaced.
class LiveEvents {
  LiveEvents({
    required this.connect,
    required this.onEvent,
    this.onConnected,
    this.onRejected,
    this.silence = const Duration(seconds: 50),
    Random? random,
  }) : _random = random ?? Random();

  /// A client for the current server (closed when its stream is done).
  final SyncApi Function() connect;

  /// Called with each event (not heartbeats).
  final void Function(ServerEvent event) onEvent;

  /// Called when a connection opened (the server is reachable again).
  final VoidCallback? onConnected;

  /// Called when the server refuses the token: sync will say so.
  final VoidCallback? onRejected;

  /// How long a connection may stay quiet before it is replaced.
  final Duration silence;

  final Random _random;

  /// Reconnection delays: doubling from [_firstRetry] to [_lastRetry].
  static const _firstRetry = Duration(seconds: 1);
  static const _lastRetry = Duration(minutes: 1);

  /// Delay after a server without the endpoint (or no Len server at all).
  static const _unsupportedRetry = Duration(minutes: 10);

  bool _on = false;
  int _attempt = 0;
  int _generation = 0;
  SyncApi? _api;
  StreamSubscription<ServerEvent?>? _subscription;
  Timer? _retry;
  Timer? _watchdog;
  bool _healthy = false;

  /// Whether a connection is open and the server has spoken on it lately:
  /// changes elsewhere are heard of within seconds.
  bool get healthy => _healthy;

  /// Connections opened so far (tests: no reconnection storms).
  int connections = 0;

  /// Opens the connection (if it is not open), or closes it.
  set run(bool on) {
    if (on == _on) return;
    _on = on;
    if (on) {
      _attempt = 0;
      _open();
    } else {
      _close();
    }
  }

  bool get run => _on;

  /// Closes the connection and opens a new one (another server or token).
  void restart() {
    if (!_on) return;
    _close();
    _attempt = 0;
    _open();
  }

  void _open() {
    _retry?.cancel();
    _retry = null;
    final generation = ++_generation;
    bool current() => _on && generation == _generation;
    connections++;
    final SyncApi api;
    try {
      api = _api = connect();
    } on SyncException {
      _scheduleRetry(_lastRetry);
      return;
    }
    _heard(generation);
    api.events().then(
      (events) {
        if (!current()) return;
        _subscription = events.listen(
          (event) {
            if (!current()) return;
            _heard(generation);
            if (!_healthy) {
              _healthy = true;
              _attempt = 0;
              onConnected?.call();
              if (!current()) return;
            }
            if (event != null) onEvent(event);
          },
          onError: (Object e) {
            if (current()) _lost();
          },
          onDone: () {
            if (current()) _lost();
          },
          cancelOnError: true,
        );
      },
      onError: (Object e) {
        if (!current()) return;
        final failure = e is SyncException ? e.kind : null;
        if (failure == SyncFailure.auth) onRejected?.call();
        _lost(
          after: switch (failure) {
            SyncFailure.incompatible => _unsupportedRetry,
            _ => null,
          },
        );
      },
    );
  }

  /// The connection [generation] spoke (or opened): it gets another
  /// [silence] before it is taken for dead.
  void _heard(int generation) {
    _watchdog?.cancel();
    _watchdog = Timer(silence, () {
      if (_on && generation == _generation) _lost();
    });
  }

  /// The connection broke (or never opened): try again after a while.
  void _lost({Duration? after}) {
    _close();
    if (_on) _scheduleRetry(after);
  }

  void _scheduleRetry(Duration? after) {
    var delay = after;
    if (delay == null) {
      final doubled = _firstRetry * pow(2, min(_attempt, 10)).toInt();
      delay = doubled > _lastRetry ? _lastRetry : doubled;
      _attempt++;
      // Up to a fifth more, so clients of a restarted server spread out.
      delay += delay * (_random.nextDouble() / 5);
    }
    _retry?.cancel();
    _retry = Timer(delay, () {
      _retry = null;
      if (_on) _open();
    });
  }

  void _close() {
    _generation++;
    _healthy = false;
    _watchdog?.cancel();
    _watchdog = null;
    _retry?.cancel();
    _retry = null;
    // (A browser may fail cancelling a stream that already broke.)
    unawaited(_subscription?.cancel().catchError((Object _) {}));
    _subscription = null;
    _api?.close();
    _api = null;
  }

  /// Closes the connection for good.
  void dispose() => run = false;
}
