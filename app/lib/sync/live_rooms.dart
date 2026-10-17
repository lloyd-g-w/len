import 'dart:async';

import 'package:flutter/foundation.dart';

import 'live_link.dart';
import 'live_messages.dart';

/// Another device in a room (an open notebook): its connection, device id
/// and the name it gave.
typedef RoomMember = ({String connection, String? deviceId, String? name});

/// An ephemeral message another device sent to a room ([LiveRooms.send]).
typedef RoomMessage = ({String room, String from, String? deviceId, Map<String, Object?> data});

/// The rooms this device is in over the live connection — one per open
/// notebook — who else is in them (presence), and the ephemeral messages
/// their members send (live ink, …), the base of real-time collaboration.
///
/// [join] and [leave] count: a notebook open in two views is joined once
/// and left when the last view closes.
class LiveRooms extends ChangeNotifier {
  LiveRooms(this._link);

  final LiveLink _link;
  final Map<String, int> _joined = {};
  final Map<String, List<RoomMember>> _others = {};
  final _messages = StreamController<RoomMessage>.broadcast(sync: true);

  /// Enters [room] (once per caller; see [leave]).
  void join(String room) {
    final n = _joined[room] = (_joined[room] ?? 0) + 1;
    if (n == 1) _link.join(room);
  }

  /// Leaves [room] once every [join] of it was left.
  void leave(String room) {
    final n = (_joined[room] ?? 0) - 1;
    if (n > 0) {
      _joined[room] = n;
      return;
    }
    _joined.remove(room);
    _link.leave(room);
    if (_others.remove(room) != null) notifyListeners();
  }

  /// The other devices in [room] (empty while not connected).
  List<RoomMember> othersIn(String room) => _others[room] ?? const [];

  /// Ephemeral messages from other members of the rooms joined.
  Stream<RoomMessage> get messages => _messages.stream;

  /// Sends [data] to the other members of [room] (only while connected,
  /// and only if someone else is there).
  void send(String room, Map<String, Object?> data) {
    if (othersIn(room).isNotEmpty) _link.sendEphemeral(room, data);
  }

  /// Takes what the server says about rooms.
  void receive(LiveMessage message) {
    switch (message) {
      case LivePresence(:final room, :final members):
        if (!_joined.containsKey(room)) return;
        final me = _link.connectionId;
        _others[room] = [
          for (final m in members)
            if (m.connection != me) m,
        ];
        notifyListeners();
      case LiveEphemeral(:final room, :final from, :final deviceId, :final data):
        if (_joined.containsKey(room)) {
          _messages.add((room: room, from: from, deviceId: deviceId, data: data));
        }
      default:
    }
  }

  /// The connection closed (or opened again): nobody is known to be here
  /// until the server says.
  void disconnected() {
    if (_others.isEmpty) return;
    _others.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_messages.close());
    super.dispose();
  }
}
