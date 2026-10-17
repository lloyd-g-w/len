import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../sync/live_rooms.dart';
import 'tools/laser.dart';

/// Where another device in a notebook's room points right now (pointers,
/// docs/SYNC_PROTOCOL.md "Room data"): its hovering pen or mouse, or its
/// laser with the laser's own dot and trail.
class RemotePointer {
  RemotePointer(this.connection, this.surface);

  /// The device's connection (presence names it).
  final String connection;

  /// The surface (page or canvas) it points at; positions are in its
  /// coordinates.
  String surface;

  /// Where it hovers, if it does (no laser then).
  Offset? hover;

  /// Its laser, replayed from what it sends (ticked by the view).
  final LaserTrail laser = LaserTrail(capacity: 1024);

  /// When it was last heard of (in sweeps).
  int heard = 0;

  /// Whether anything of it shows.
  bool get shows => hover != null || laser.isVisible;
}

/// The pointers of the other devices in a notebook's room: shown live,
/// hidden after [silence] without news (a mouse at rest, a device gone
/// quiet), and at once when the device leaves the room (or this device's
/// connection drops).
class RemotePointers extends ChangeNotifier {
  RemotePointers(this.rooms, {required this.room}) {
    _subscription = rooms.messages.where((m) => m.room == room).listen(receive);
    rooms.addListener(_membersChanged);
  }

  final LiveRooms rooms;
  final String room;

  /// How long a pointer shows without news.
  static const silence = Duration(seconds: 3);

  late final StreamSubscription<RoomMessage> _subscription;
  final Map<String, RemotePointer> _pointers = {};
  Timer? _sweep;
  int _now = 0; // Sweeps (half seconds).

  /// The pointers shown, in the order they came.
  Iterable<RemotePointer> get pointers => _pointers.values;
  bool get isEmpty => _pointers.isEmpty;

  /// Whether frames change anything (a laser trail fading).
  bool get animating => _pointers.values.any((p) => p.laser.animating);

  /// The name device [connection] gave, if it is in the room.
  String? nameOf(String connection) {
    for (final m in rooms.othersIn(room)) {
      if (m.connection == connection) return m.name;
    }
    return null;
  }

  /// Advances the lasers to frame time [nowMs] (see [LaserTrail.tick]).
  void tick(double nowMs) {
    if (_pointers.isEmpty) return;
    for (final p in _pointers.values) {
      p.laser.tick(nowMs);
    }
    _pointers.removeWhere((_, p) => !p.shows);
    notifyListeners();
  }

  /// Takes a message of the room.
  void receive(RoomMessage message) {
    final data = message.data;
    final page = data['page'];
    if (message.room != room || data['k'] != 'pointer' || page is! String) return;
    final p = _pointers[message.from] ??= RemotePointer(message.from, page);
    if (p.surface != page) {
      // Moved to another page: what showed was in the old one's coordinates.
      p
        ..surface = page
        ..hover = null
        ..laser.clear();
    }
    p.heard = _now;
    final at = _offset(data['at'], 0);
    final laser = data['laser'];
    if (laser is Map) {
      p.hover = null;
      _replay(p.laser, laser, at);
    } else {
      p.hover = at;
      p.laser
        ..up()
        ..hover(null);
    }
    _sweep ??= Timer.periodic(const Duration(milliseconds: 500), (_) => _expire());
    notifyListeners();
  }

  /// Plays what a device's laser did on [trail]: its new trail points
  /// (strokes starting where `starts` says), then whether it is down and
  /// where its dot is ([at]).
  static void _replay(LaserTrail trail, Map<Object?, Object?> laser, Offset? at) {
    final color = laser['color'], size = laser['size'];
    trail.config = LaserConfig.fromJson({
      'mode': laser['mode'],
      'colors': [color],
      'color': 0,
      'sizes': [size],
      'size': 0,
      'duration': laser['duration'],
      'fade': laser['fade'],
      'hold': laser['hold'],
    });
    final points = laser['p'];
    final starts = laser['starts'];
    final startSet = starts is List ? starts.whereType<int>().toSet() : const <int>{};
    if (points is List) {
      for (var i = 0; 2 * i + 1 < points.length; i++) {
        final point = _offset(points, 2 * i);
        if (point == null) break;
        if (startSet.contains(i) || !trail.pressed) {
          trail
            ..up()
            ..down(point);
        } else {
          trail.move(point);
        }
      }
    }
    final down = laser['down'] == true;
    if (!down) {
      trail.up();
    } else if (at != null) {
      trail.pressed ? trail.move(at, record: false) : trail.down(at);
    }
    trail.hover(laser['hover'] == true && !down ? at : null);
  }

  static Offset? _offset(Object? list, int i) {
    if (list is! List || list.length < i + 2) return null;
    final (x, y) = (list[i], list[i + 1]);
    return x is num && y is num && x.isFinite && y.isFinite
        ? Offset(x.toDouble(), y.toDouble())
        : null;
  }

  void _expire() {
    _now++;
    final quiet = silence.inMilliseconds ~/ 500;
    var hidden = false;
    for (final p in _pointers.values) {
      if (_now - p.heard != quiet) continue;
      hidden = true;
      p
        ..hover = null
        ..laser.up()
        ..laser.hover(null);
    }
    // A laser nobody ticks (no view shows it) fades no further: it goes too.
    if (!_drop((p) => !p.shows || _now - p.heard >= 2 * quiet) && hidden) notifyListeners();
  }

  void _membersChanged() {
    if (_pointers.isEmpty) return;
    final members = {for (final m in rooms.othersIn(room)) m.connection};
    _drop((p) => !members.contains(p.connection));
  }

  /// Drops the pointers [gone] says (and tells, if any); ends the sweeps
  /// once none is left.
  bool _drop(bool Function(RemotePointer p) gone) {
    final before = _pointers.length;
    _pointers.removeWhere((_, p) => gone(p));
    if (_pointers.isEmpty) {
      _sweep?.cancel();
      _sweep = null;
    }
    if (_pointers.length == before) return false;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    rooms.removeListener(_membersChanged);
    unawaited(_subscription.cancel());
    _sweep?.cancel();
    super.dispose();
  }
}
