import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/syncable.dart';
import 'live_channel.dart';
import 'live_messages.dart';
import 'sync_engine.dart' show LivePushException;

/// Keeps one live connection (`/v1/live`) open while [run] is on,
/// reconnecting with backoff: hands what the server sends to [onMessage],
/// sends pushes and answers their replies, and keeps this device in its
/// [rooms] (joined again after reconnecting).
///
/// A connection that has said nothing for [silence] (the server sends a
/// heartbeat every 20 s) is taken for dead and replaced.
class LiveLink {
  LiveLink({
    required this.connect,
    required this.onMessage,
    this.onChanged,
    this.identity,
    this.silence = const Duration(seconds: 50),
    this.pushTimeout = const Duration(seconds: 15),
    Random? random,
  }) : _random = random ?? Random();

  /// Opens a connection to the current server; throws if it cannot.
  final Future<LiveChannel> Function() connect;

  /// Called with each message but replies to pushes (and heartbeats).
  final void Function(LiveMessage message) onMessage;

  /// Called when [healthy] or [failures] changed.
  final VoidCallback? onChanged;

  /// Who this device is in rooms (`hello`): its id and a name to show.
  final ({String deviceId, String? name}) Function()? identity;

  /// How long a connection may stay quiet before it is replaced.
  final Duration silence;

  /// How long a push may wait for its answer.
  final Duration pushTimeout;

  final Random _random;

  static const _firstRetry = Duration(seconds: 1);
  static const _lastRetry = Duration(minutes: 1);

  bool _on = false;
  int _attempt = 0;
  int _generation = 0;
  LiveChannel? _channel;
  StreamSubscription<String>? _subscription;
  Timer? _retry;
  Timer? _watchdog;
  bool _healthy = false;
  int _nextId = 0;
  final Map<int, Completer<LivePushed>> _pushes = {};

  /// Whether a connection is open and greeted (`hello`).
  bool get healthy => _healthy;

  /// Connection attempts in a row that never got as far as `hello`.
  int get failures => _failures;
  int _failures = 0;

  /// Connections opened so far (tests: no reconnection storms).
  int connections = 0;

  /// This connection's id at the server (as rooms show it), once greeted.
  String? connectionId;

  /// Rooms this device is in (kept across reconnections).
  final Set<String> rooms = {};

  bool get run => _on;

  /// Opens the connection (if it is not open), or closes it.
  set run(bool on) {
    if (on == _on) return;
    _on = on;
    if (on) {
      _attempt = 0;
      _open();
    } else {
      _close();
      _failures = 0;
      onChanged?.call();
    }
  }

  /// Closes the connection and opens a new one (another server or token).
  void restart() {
    if (!_on) return;
    _close();
    _attempt = 0;
    _failures = 0;
    _open();
  }

  /// Pushes [records] (see [LivePush]); throws [LivePushException].
  Future<LivePushed> push(
    List<SyncRecord> records, {
    required int since,
    required bool current,
  }) async {
    final channel = _channel;
    if (!_healthy || channel == null) throw const LivePushException('not connected');
    final id = ++_nextId;
    final String text;
    try {
      text =
          '{"type":"push","id":$id,"since":$since,"current":$current,"records":'
          '[${records.map((r) => jsonEncode(r.toJson())).join(',')}]}';
    } on JsonUnsupportedObjectError catch (e) {
      throw LivePushException('cannot encode: ${e.cause ?? e}');
    }
    final answer = _pushes[id] = Completer<LivePushed>();
    final generation = _generation;
    channel.send(text);
    try {
      return await answer.future.timeout(pushTimeout);
    } on TimeoutException {
      // The connection is gone without saying so: a new one.
      if (_on && generation == _generation) _lost();
      throw const LivePushException('no answer');
    } finally {
      _pushes.remove(id);
    }
  }

  /// Enters [room] (a notebook): this device shows in its presence and
  /// hears its ephemeral messages.
  void join(String room) {
    if (rooms.add(room)) _send({'type': 'join', 'room': room});
  }

  void leave(String room) {
    if (rooms.remove(room)) _send({'type': 'leave', 'room': room});
  }

  /// Sends [data] to the other members of [room] (dropped while not
  /// connected: it is live state).
  void sendEphemeral(String room, Map<String, Object?> data) {
    if (rooms.contains(room)) _send({'type': 'ephemeral', 'room': room, 'data': data});
  }

  void _send(Map<String, Object?> message) {
    if (_healthy) _channel?.send(jsonEncode(message));
  }

  void _open() {
    _retry?.cancel();
    _retry = null;
    final generation = ++_generation;
    bool current() => _on && generation == _generation;
    connections++;
    _heard(generation);
    connect().then(
      (channel) {
        if (!current()) {
          channel.close();
          return;
        }
        _channel = channel;
        _subscription = channel.messages.listen(
          (text) {
            if (current()) _receive(text, generation);
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
        debugPrint('Live connection failed: $e');
        _lost();
      },
    );
  }

  void _receive(String text, int generation) {
    _heard(generation);
    final message = LiveMessage.parse(text);
    switch (message) {
      case LiveHello(:final connection):
        connectionId = connection;
        _healthy = true;
        _attempt = 0;
        _failures = 0;
        if (identity?.call() case final me?) {
          _send({'type': 'hello', 'deviceId': me.deviceId, 'name': ?me.name});
        }
        for (final room in rooms) {
          _send({'type': 'join', 'room': room});
        }
        onChanged?.call();
        if (generation != _generation) return;
      case LivePushed(:final id) when id is int && _pushes.containsKey(id):
        _pushes[id]!.complete(message);
        return;
      case LiveError(:final id) when id is int && _pushes.containsKey(id):
        _pushes[id]!.completeError(
          LivePushException(message.error, status: message.status, index: message.index),
        );
        return;
      default:
    }
    onMessage(message);
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
  void _lost() {
    if (!_healthy) _failures++;
    _close();
    onChanged?.call();
    if (!_on) return;
    final doubled = _firstRetry * pow(2, min(_attempt, 10)).toInt();
    var delay = doubled > _lastRetry ? _lastRetry : doubled;
    _attempt++;
    // Up to a fifth more, so clients of a restarted server spread out.
    delay += delay * (_random.nextDouble() / 5);
    _retry = Timer(delay, () {
      _retry = null;
      if (_on) _open();
    });
  }

  void _close() {
    _generation++;
    _healthy = false;
    connectionId = null;
    _watchdog?.cancel();
    _watchdog = null;
    _retry?.cancel();
    _retry = null;
    unawaited(_subscription?.cancel().catchError((Object _) {}));
    _subscription = null;
    _channel?.close();
    _channel = null;
    for (final p in _pushes.values) {
      if (!p.isCompleted) p.completeError(const LivePushException('connection closed'));
    }
    _pushes.clear();
  }

  /// Closes the connection for good.
  void dispose() => run = false;
}
