/// `GET /v1/live`: live connections, their rooms and what they are sent
/// (docs/SYNC_PROTOCOL.md, "Live connection").
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocketStatus;

import 'live_connection.dart';
import 'record.dart';

export 'live_connection.dart' show LiveConnection, LiveKind, LiveLimits, LivePeer;

/// Handles a `push` message from [from]: returns the reply (`pushed` or
/// `error`), after announcing what it stored.
typedef LivePushHandler =
    Map<String, Object?> Function(Map<String, Object?> message, LiveConnection from);

/// The server's change feed position: its newest seq and its id.
typedef FeedPosition = ({int seq, String serverId});

/// Open live connections: fans out stored records to every connection but
/// the pushing one, answers pushes, relays `ephemeral` messages within
/// rooms and tells rooms who is in them (`presence`).
class LiveHub {
  LiveHub({this.limits = const LiveLimits()});

  final LiveLimits limits;

  /// The feed position (set by `buildHandler`).
  FeedPosition Function() feed = () => (seq: 0, serverId: '');

  /// Stores pushed records (set by `buildHandler`).
  LivePushHandler? onPush;

  final Map<String, LiveConnection> _connections = {};
  final Map<String, Set<LiveConnection>> _rooms = {};
  Timer? _heartbeat;
  int _ids = 0;
  bool _closed = false;

  /// Number of open connections.
  int get connections => _connections.length;

  /// The connection with [id], if open (tests).
  LiveConnection? connection(String id) => _connections[id];

  /// Whether another connection is accepted.
  bool get acceptsMore => !_closed && _connections.length < limits.maxConnections;

  /// Takes on a client's connection; it is greeted with `hello`.
  LiveConnection accept(LivePeer peer) {
    final id = 'c${++_ids}';
    final connection = LiveConnection(id, peer, limits, onMessage: _onMessage, onDone: _onDone)
      ..resyncText = _resyncText;
    _connections[id] = connection;
    final position = feed();
    connection.send({
      'type': 'hello',
      'protocol': 1,
      'serverId': position.serverId,
      'seq': position.seq,
      'connection': id,
      'heartbeat': limits.heartbeat.inSeconds,
    }, LiveKind.reply);
    _heartbeat ??= Timer.periodic(limits.heartbeat, (_) => _beat());
    return connection;
  }

  /// Sends records a push just [stored] (consecutive seqs) to every
  /// connection but [except] (the pusher, which knows them). Records too
  /// large for one message are announced with `resync` (clients pull).
  void publishRecords(List<SyncRecord> stored, {LiveConnection? except}) {
    if (stored.isEmpty || _connections.isEmpty) return;
    final first = stored.first.seq!;
    final last = stored.last.seq!;
    final text = jsonEncode({
      'type': 'records',
      'prevSeq': first - 1,
      'seq': last,
      'records': [for (final r in stored) r.toJson()],
    });
    final fits = text.length <= limits.maxRecordsFrameBytes;
    final resync = fits ? null : _resyncText();
    for (final c in _connections.values) {
      if (identical(c, except)) continue;
      c.sendText(resync ?? text, fits ? LiveKind.records : LiveKind.resync);
    }
  }

  /// Tells every connection to pull: the feed changed in a way records
  /// messages cannot tell (the server took a new id).
  void publishResync() {
    final text = _resyncText();
    for (final c in _connections.values) {
      c.sendText(text, LiveKind.resync);
    }
  }

  String _resyncText() {
    final position = feed();
    return jsonEncode({'type': 'resync', 'seq': position.seq, 'serverId': position.serverId});
  }

  /// Closes every connection (going away) and refuses new ones.
  Future<void> close() async {
    _closed = true;
    _heartbeat?.cancel();
    await Future.wait([
      for (final c in _connections.values.toList())
        c.close(WebSocketStatus.goingAway, 'server shutting down'),
    ]);
  }

  void _beat() {
    if (_connections.isEmpty) {
      _heartbeat?.cancel();
      _heartbeat = null;
      return;
    }
    const text = '{"type":"heartbeat"}';
    for (final c in _connections.values) {
      c.sendText(text, LiveKind.reply);
    }
  }

  void _onDone(LiveConnection c) {
    if (_connections.remove(c.id) == null) return;
    for (final room in c.rooms.toList()) {
      _leave(c, room);
    }
  }

  void _onMessage(LiveConnection from, Map<String, Object?> m) {
    final id = m['id'];
    void error(String message) =>
        from.send({'type': 'error', 'id': ?id, 'error': message}, LiveKind.reply);
    switch (m['type']) {
      case 'hello':
        final deviceId = m['deviceId'];
        final name = m['name'];
        if (deviceId is! String? || (deviceId != null && !_validId(deviceId))) {
          return error('deviceId must be 1..64 characters');
        }
        if (name is! String? || (name != null && name.length > 64)) {
          return error('name must be at most 64 characters');
        }
        from
          ..deviceId = deviceId
          ..name = name;
        for (final room in from.rooms) {
          _presence(room);
        }
      case 'push':
        final handler = onPush;
        if (handler == null) return error('push unavailable');
        from.send(handler(m, from), LiveKind.reply);
      case 'join':
        final room = m['room'];
        if (room is! String || !_validId(room)) return error('room must be 1..64 characters');
        if (from.rooms.contains(room)) return;
        if (from.rooms.length >= limits.maxRooms) {
          return error('at most ${limits.maxRooms} rooms');
        }
        from.rooms.add(room);
        (_rooms[room] ??= {}).add(from);
        _presence(room);
      case 'leave':
        final room = m['room'];
        if (room is String) _leave(from, room);
      case 'ephemeral':
        _relay(from, m);
      case 'ping':
        from.send({'type': 'pong', 'id': ?id}, LiveKind.reply);
      default:
        error('unknown message type');
    }
  }

  /// Relays an `ephemeral` message to the other members of its room,
  /// within size and rate limits (dropped beyond them: it is live state,
  /// soon replaced by the next).
  void _relay(LiveConnection from, Map<String, Object?> m) {
    final room = m['room'];
    final data = m['data'];
    if (room is! String || !from.rooms.contains(room) || data is! Map<String, Object?>) {
      from.send({
        'type': 'error',
        'error': 'ephemeral needs a joined room and data',
      }, LiveKind.reply);
      return;
    }
    final members = _rooms[room];
    if (members == null || members.length < 2 || !from.takeEphemeralToken()) return;
    final text = jsonEncode({
      'type': 'ephemeral',
      'room': room,
      'from': from.id,
      'deviceId': ?from.deviceId,
      'data': data,
    });
    if (text.length > limits.maxEphemeralBytes) {
      from.send({'type': 'error', 'error': 'ephemeral message too large'}, LiveKind.reply);
      return;
    }
    for (final c in members) {
      if (!identical(c, from)) c.sendText(text, LiveKind.ephemeral, room: room);
    }
  }

  void _leave(LiveConnection c, String room) {
    if (!c.rooms.remove(room)) return;
    final members = _rooms[room];
    members?.remove(c);
    if (members == null || members.isEmpty) {
      _rooms.remove(room);
    } else {
      _presence(room);
    }
  }

  /// Tells the members of [room] who is in it.
  void _presence(String room) {
    final members = _rooms[room];
    if (members == null) return;
    final text = jsonEncode({
      'type': 'presence',
      'room': room,
      'members': [
        for (final c in members) {'connection': c.id, 'deviceId': ?c.deviceId, 'name': ?c.name},
      ],
    });
    for (final c in members) {
      c.sendText(text, LiveKind.presence, room: room);
    }
  }

  static bool _validId(String s) => s.isNotEmpty && s.length <= SyncRecord.maxIdLength;
}
