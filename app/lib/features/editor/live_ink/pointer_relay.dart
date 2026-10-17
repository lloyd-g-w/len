import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../ink/input/ink_events.dart';
import '../../../ink/tools/laser.dart';

/// Shows where this editor points to the other devices in its notebook's
/// room (pointers, docs/SYNC_PROTOCOL.md "Room data"): a hovering pen or
/// mouse, and the laser's dot and trail, at most every [every].
///
/// Costs nothing while nobody else is in the room: it hooks into the
/// input and the laser only while someone is ([presence] tells).
class PointerRelay {
  PointerRelay({
    required this.events,
    required this.laser,
    required this.surface,
    required this.send,
    required this.presence,
    required this.anyoneThere,
    this.every = const Duration(milliseconds: 40),
  }) {
    presence.addListener(_presenceChanged);
    _presenceChanged();
  }

  /// The main input's events (hovering).
  final InkEvents events;

  /// The laser pointer of this editor (in [surface]'s coordinates).
  final LaserTrail laser;

  /// The surface (page or canvas) the input and the laser are on now.
  final String Function() surface;

  /// Sends a message to the room (dropped while not connected).
  final void Function(Map<String, Object?> data) send;

  /// Notifies when the room's members change; [anyoneThere] tells whether
  /// another device is in the room.
  final Listenable presence;
  final bool Function() anyoneThere;

  /// The least time between two messages (25 a second).
  final Duration every;

  /// How often a laser held still (pressed or hovering) is told again, so
  /// other devices keep showing it (they hide pointers they don't hear of
  /// for a while).
  static const keepAlive = Duration(seconds: 1);

  /// Trail points per message at most (more wait for the next).
  static const maxPoints = 200;

  bool _attached = false;
  Offset? _hover;
  int _seen = 0; // Laser points sent or skipped ([LaserTrail.added]).
  final List<double> _points = [];
  final List<int> _starts = [];
  Timer? _timer;
  Timer? _alive;
  bool _due = false;
  String? _last; // What the last message said (no repeats).

  void _presenceChanged() {
    final there = anyoneThere();
    if (there == _attached) return;
    _attached = there;
    if (there) {
      events.hovered = _hovered;
      laser.addListener(_laserChanged);
      _seen = laser.added;
      return;
    }
    if (events.hovered == _hovered) events.hovered = null;
    laser.removeListener(_laserChanged);
    _hover = null;
    _points.clear();
    _starts.clear();
    _timer?.cancel();
    _timer = null;
    _alive?.cancel();
    _alive = null;
    _last = null;
  }

  void _hovered(Offset? world) {
    if (world == _hover) return;
    _hover = world;
    _changed();
  }

  void _laserChanged() {
    final added = laser.added;
    if (added != _seen) {
      final n = added - _seen < laser.length ? added - _seen : laser.length;
      for (var i = laser.length - n; i < laser.length; i++) {
        if (laser.startsAt(i)) _starts.add(_points.length ~/ 3);
        final p = laser.pointAt(i);
        _points.addAll([_round(p.dx), _round(p.dy), (laser.pressureAt(i) * 1000).round() / 1000]);
      }
      _seen = added;
    }
    _changed(); // Frames of a fading trail say nothing new: not sent.
  }

  void _changed() {
    if (_timer != null) {
      _due = true;
      return;
    }
    _flush();
  }

  /// Sends what changed, then waits [every] before the next.
  void _flush() {
    _due = false;
    final message = _message();
    final said = message.toString();
    if (said != _last) {
      _last = said;
      send(message);
      _timer = Timer(every, () {
        _timer = null;
        if (_due) _flush();
      });
    }
    _alive?.cancel();
    _alive = laser.pressed || laser.hovering
        ? Timer(keepAlive, () {
            _last = null;
            _flush();
          })
        : null;
  }

  Map<String, Object?> _message() {
    final laserShows = laser.pressed || laser.hovering || _points.isNotEmpty;
    final head = laser.head;
    final at = laserShows ? head : _hover;
    final Map<String, Object?>? laserData;
    if (laserShows) {
      final c = laser.config;
      final take = _points.length > maxPoints * 3 ? maxPoints * 3 : _points.length;
      final starts = [
        for (final s in _starts)
          if (s * 3 < take) s,
      ];
      laserData = {
        'mode': c.mode.name,
        'color': c.color,
        'size': c.size,
        'duration': c.duration.inMilliseconds,
        'fade': c.fade.name,
        'hold': c.hold.inMilliseconds,
        'down': laser.pressed,
        if (laser.hovering) 'hover': true,
        if (take > 0) 'p': _points.sublist(0, take),
        if (starts.isNotEmpty) 'starts': starts,
      };
      _points.removeRange(0, take);
      final rest = [
        for (final s in _starts)
          if (s * 3 >= take) s - take ~/ 3,
      ];
      _starts
        ..clear()
        ..addAll(rest);
      if (_points.isNotEmpty) _due = true;
    } else {
      laserData = null;
    }
    return {
      'k': 'pointer',
      'page': surface(),
      if (at != null) 'at': [_round(at.dx), _round(at.dy)],
      'laser': ?laserData,
    };
  }

  /// To a hundredth of a world unit.
  static double _round(double v) => (v * 100).round() / 100;

  void dispose() {
    presence.removeListener(_presenceChanged);
    if (_attached) {
      if (events.hovered == _hovered) events.hovered = null;
      laser.removeListener(_laserChanged);
    }
    _timer?.cancel();
    _alive?.cancel();
  }
}
