/// One live connection (`GET /v1/live`): its transport, its bounded outbox
/// and what the client told about itself.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show WebSocket, WebSocketStatus;

/// The transport of a live connection as the hub sees it: messages in,
/// messages out (bound once, so the transport's backpressure reaches the
/// outbox), closing.
class LivePeer {
  LivePeer({
    required this.incoming,
    required this.outgoing,
    required this.close,
    required this.destroy,
  });

  /// A server-side WebSocket; [destroy] drops its connection at once.
  factory LivePeer.webSocket(WebSocket socket, {required void Function() destroy}) => LivePeer(
    incoming: socket,
    outgoing: socket,
    close: (code, reason) => socket.close(code, reason),
    destroy: destroy,
  );

  /// Messages from the client: text frames are `String`s.
  final Stream<Object?> incoming;

  /// Messages to the client.
  final StreamConsumer<Object?> outgoing;

  /// Ends the connection with a close [code] once everything was sent.
  final Future<void> Function(int code, String reason) close;

  /// Drops the connection without sending anything more (a stuck client).
  final void Function() destroy;
}

/// What an outgoing message is, for dropping messages when a client
/// cannot keep up: changes become one `resync`, live messages are dropped,
/// replies always stay.
enum LiveKind { records, resync, ephemeral, presence, reply }

/// Settings of live connections.
class LiveLimits {
  const LiveLimits({
    this.maxConnections = 1000,
    this.heartbeat = const Duration(seconds: 20),
    this.maxQueuedBytes = 1024 * 1024,
    this.stallTimeout = const Duration(seconds: 30),
    this.maxMessageBytes = 4 * 1024 * 1024,
    this.maxRecordsFrameBytes = 1024 * 1024,
    this.maxEphemeralBytes = 16 * 1024,
    this.ephemeralPerSecond = 40,
    this.ephemeralBurst = 80,
    this.maxRooms = 8,
  });

  /// Connections beyond this many are refused (`503`).
  final int maxConnections;

  /// How often a connection carries a `heartbeat` message.
  final Duration heartbeat;

  /// Bytes waiting for a client that does not read before its changes are
  /// replaced by one `resync` (pull) and live messages dropped.
  final int maxQueuedBytes;

  /// How long a client may read nothing while messages wait before its
  /// connection is dropped.
  final Duration stallTimeout;

  /// The largest message a client may send; larger ones close the
  /// connection (1009).
  final int maxMessageBytes;

  /// Stored records whose message would be larger are announced with
  /// `resync` instead (clients pull them).
  final int maxRecordsFrameBytes;

  /// The largest `ephemeral` message relayed.
  final int maxEphemeralBytes;

  /// `ephemeral` messages a connection may send per second on average, and
  /// in a burst; beyond that they are dropped.
  final double ephemeralPerSecond;
  final double ephemeralBurst;

  /// Rooms one connection may be in.
  final int maxRooms;
}

/// One client's live connection.
class LiveConnection {
  LiveConnection(
    this.id,
    this._peer,
    this.limits, {
    required this.onMessage,
    required this.onDone,
  }) {
    _out = StreamController<String>(onResume: _flush, onPause: _paused);
    unawaited(
      _peer.outgoing
          .addStream(_out.stream)
          .then<void>((_) {}, onError: (Object _) {})
          .whenComplete(() => _sent.complete()),
    );
    _incoming = _peer.incoming.listen(
      _receive,
      onError: (Object _) => _end(),
      onDone: _end,
      cancelOnError: true,
    );
    _tokens = limits.ephemeralBurst;
    _refilled = _clock.elapsedMicroseconds;
  }

  /// This connection's id (in presence and relayed messages).
  final String id;
  final LivePeer _peer;
  final LiveLimits limits;

  /// Called with each message the client sends (a decoded JSON object).
  final void Function(LiveConnection from, Map<String, Object?> message) onMessage;

  /// Called once the connection is gone.
  final void Function(LiveConnection connection) onDone;

  /// What the client said of itself (`hello`).
  String? deviceId;
  String? name;

  /// Rooms joined.
  final Set<String> rooms = {};

  late final StreamController<String> _out;
  late final StreamSubscription<Object?> _incoming;
  final _sent = Completer<void>();
  final _queue = ListQueue<({String text, LiveKind kind, String? room})>();
  int _queuedBytes = 0;
  bool _resyncQueued = false;
  Timer? _stall;
  bool _closed = false;

  /// Messages dropped because the client could not keep up (tests).
  int dropped = 0;

  final _clock = Stopwatch()..start();
  late double _tokens;
  late int _refilled;

  bool get closed => _closed;

  /// Sends [message] (encoded once by the caller for many connections).
  void sendText(String text, LiveKind kind, {String? room}) {
    if (_closed) return;
    if (kind == LiveKind.records && _resyncQueued) {
      dropped++;
      return; // The queued resync makes the client pull these too.
    }
    if (_queue.isEmpty && !_out.isPaused) {
      _out.add(text);
      return;
    }
    _queue.add((text: text, kind: kind, room: room));
    _queuedBytes += text.length;
    if (kind == LiveKind.resync) _resyncQueued = true;
    if (_queuedBytes > limits.maxQueuedBytes) _compact();
  }

  /// Encodes and sends [message].
  void send(Map<String, Object?> message, LiveKind kind) => sendText(jsonEncode(message), kind);

  /// Whether an `ephemeral` message may go now (token bucket).
  bool takeEphemeralToken() {
    final now = _clock.elapsedMicroseconds;
    _tokens = (_tokens + (now - _refilled) / 1e6 * limits.ephemeralPerSecond).clamp(
      0,
      limits.ephemeralBurst,
    );
    _refilled = now;
    if (_tokens < 1) return false;
    _tokens--;
    return true;
  }

  /// A client that does not keep up: its changes become one `resync`,
  /// live messages (ephemeral, all but the newest presence per room) go.
  void _compact() {
    final kept = ListQueue<({String text, LiveKind kind, String? room})>();
    final presence = <String?, ({String text, LiveKind kind, String? room})>{};
    for (final m in _queue) {
      switch (m.kind) {
        case LiveKind.reply:
          kept.add(m);
        case LiveKind.presence:
          presence[m.room] = m;
        case LiveKind.records || LiveKind.resync || LiveKind.ephemeral:
          dropped++;
      }
    }
    kept.addAll(presence.values);
    kept.add((text: resyncText?.call() ?? '{"type":"resync"}', kind: LiveKind.resync, room: null));
    _queue
      ..clear()
      ..addAll(kept);
    _queuedBytes = kept.fold(0, (n, m) => n + m.text.length);
    _resyncQueued = true;
  }

  /// The `resync` message to queue for a client that fell behind.
  String Function()? resyncText;

  void _paused() {
    _stall ??= Timer(limits.stallTimeout, () {
      if (_out.isPaused && !_closed) {
        _closed = true;
        _peer.destroy();
        _end();
      }
    });
  }

  void _flush() {
    _stall?.cancel();
    _stall = null;
    while (_queue.isNotEmpty && !_out.isPaused && !_out.isClosed) {
      final m = _queue.removeFirst();
      _queuedBytes -= m.text.length;
      if (m.kind == LiveKind.resync) {
        _resyncQueued = false;
        // Written now, so its seq covers the records dropped meanwhile.
        _out.add(resyncText?.call() ?? m.text);
        continue;
      }
      _out.add(m.text);
    }
  }

  void _receive(Object? raw) {
    if (_closed) return;
    if (raw is! String) {
      unawaited(close(WebSocketStatus.unsupportedData, 'text frames only'));
      return;
    }
    if (raw.length > limits.maxMessageBytes) {
      unawaited(close(WebSocketStatus.messageTooBig, 'message too big'));
      return;
    }
    final Object? message;
    try {
      message = jsonDecode(raw);
    } on FormatException {
      send({'type': 'error', 'error': 'message must be JSON'}, LiveKind.reply);
      return;
    }
    if (message is! Map<String, Object?> || message['type'] is! String) {
      send({'type': 'error', 'error': 'message must be an object with a type'}, LiveKind.reply);
      return;
    }
    onMessage(this, message);
  }

  /// Ends the connection with [code] after what is queued was sent (a
  /// client that does not read is dropped after 5 s).
  Future<void> close(int code, String reason) async {
    if (_closed) return;
    _closed = true;
    _end();
    _flush();
    unawaited(_out.close());
    await _sent.future.timeout(const Duration(seconds: 5), onTimeout: _peer.destroy);
    try {
      await _peer.close(code, reason).timeout(const Duration(seconds: 5));
    } on Object {
      _peer.destroy();
    }
  }

  bool _done = false;

  void _end() {
    if (_done) return;
    _done = true;
    _stall?.cancel();
    unawaited(_incoming.cancel());
    onDone(this);
    if (!_closed) {
      // The client left: nothing more to send.
      _closed = true;
      unawaited(_out.close());
    }
  }
}
