import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../domain/stroke.dart';
import '../../../ink/input/ink_events.dart';
import '../../../ink/input/live_ink.dart';

/// Sends the stroke this editor is writing to the other devices in its
/// notebook's room as it grows (live ink, docs/SYNC_PROTOCOL.md "Room
/// data"): its new points at most every [every], and its end with the ids
/// of the strokes it became, so they draw it until those strokes arrive.
/// A device joining the room mid-stroke gets the stroke again from its
/// start, so it shows it live too.
class LiveInkRelay {
  LiveInkRelay({
    required this.live,
    required InkEvents events,
    required this.send,
    required this.anyoneThere,
    this.presence,
    this.members,
    this.every = const Duration(milliseconds: 50),
  }) {
    attach(events);
    live.addListener(_changed);
    _members = {...?members?.call()};
    presence?.addListener(_presenceChanged);
  }

  final LiveInk live;
  final List<InkEvents> _events = [];

  /// Relays the strokes [events] tells of too (another input writing into
  /// [live]: the zoom window).
  void attach(InkEvents events) {
    _events.add(
      events
        ..inkBegan = _began
        ..inkEnded = _ended,
    );
  }

  /// Sends a message to the room (dropped while not connected).
  final void Function(Map<String, Object?> data) send;

  /// Whether another device is in the room (nothing is sent otherwise).
  final bool Function() anyoneThere;

  /// Notifies when the room's members change; [members] are the other
  /// devices' connections. A device joining mid-stroke gets it again from
  /// its start.
  final Listenable? presence;
  final Iterable<String> Function()? members;

  /// The least time between two messages of a stroke.
  final Duration every;

  /// How often a stroke whose pen rests is told again (no new points), so
  /// other devices keep showing it (they drop writers they don't hear of
  /// for a while, [RemoteInk.silence]).
  static const keepAlive = Duration(seconds: 1);

  /// Points per message at most (a stroke replaced whole, e.g. snapped to
  /// a shape, goes in several).
  static const maxPoints = 300;

  static final _random = Random();

  String? _id;
  String? _surface; // Of the stroke being written (sent or not).
  Set<String> _members = const {};
  int _sent = 0;
  int _generation = 0;
  Timer? _timer;
  Timer? _alive;
  bool _due = false;

  /// Whether the stroke being written is shown to other devices.
  bool get relaying => _id != null;

  void _began(String surfaceId) {
    _timer?.cancel();
    _timer = null;
    _alive?.cancel();
    _surface = surfaceId;
    if (!anyoneThere()) {
      _id = null;
      return;
    }
    _id = _newId();
    _sent = 0;
    _generation = live.generation;
    _flush();
  }

  static String _newId() =>
      '${_random.nextInt(1 << 30).toRadixString(36)}${_random.nextInt(1 << 30).toRadixString(36)}';

  /// Someone joined mid-stroke: the stroke goes again from its start (in
  /// messages of [maxPoints], as a stroke replaced whole), so they show it
  /// all; those who showed it already replace its points.
  void _presenceChanged() {
    final now = {...?members?.call()};
    final joined = now.any((m) => !_members.contains(m));
    _members = now;
    if (!joined || _surface == null || !live.isDrawing || !anyoneThere()) return;
    _id ??= _newId(); // Nobody was there when it began.
    _sent = 0;
    _generation = live.generation;
    if (_timer != null) {
      _due = true;
    } else {
      _flush();
    }
  }

  void _changed() {
    if (_id == null || !live.isDrawing) return;
    if (_timer != null) {
      _due = true;
      return;
    }
    _flush();
  }

  /// Sends the points not sent yet, then waits [every] before the next.
  void _flush() {
    final id = _id;
    if (id == null) return;
    _due = false;
    final points = live.points;
    if (live.generation != _generation) {
      _generation = live.generation;
      _sent = 0; // Replaced (straightened, snapped): again from the start.
    }
    if (points.length > _sent) {
      final end = min(points.length, _sent + maxPoints);
      _send(id, [for (final p in points.sublist(_sent, end)) ..._rounded(p)]);
      _sent = end;
      if (end < points.length) _due = true;
    }
    _timer = Timer(every, () {
      _timer = null;
      if (_due) _flush();
    });
  }

  /// Sends the points [p] (flattened) from [_sent] on, and tells the
  /// stroke again after [keepAlive] if nothing else was sent meanwhile.
  void _send(String id, List<num> p) {
    send({
      'k': 'ink',
      's': id,
      'page': _surface,
      'tool': live.tool.name,
      'color': live.color,
      'width': live.width,
      'style': live.style.toJson(),
      'from': _sent,
      'p': p,
    });
    _alive?.cancel();
    _alive = Timer(keepAlive, () {
      if (_id == id && live.isDrawing) _send(id, const []);
    });
  }

  /// [p] as sent: positions to a hundredth of a world unit, pressure to a
  /// thousandth (enough to draw it; the stroke's record follows).
  static List<num> _rounded(StrokePoint p) => [
    (p.x * 100).round() / 100,
    (p.y * 100).round() / 100,
    (p.pressure * 1000).round() / 1000,
  ];

  void _ended(List<String> strokeIds) {
    final id = _id;
    _id = null;
    _surface = null;
    _timer?.cancel();
    _timer = null;
    _alive?.cancel();
    if (id == null) return;
    send({'k': 'ink', 's': id, 'end': true, if (strokeIds.isNotEmpty) 'strokes': strokeIds});
  }

  void dispose() {
    live.removeListener(_changed);
    presence?.removeListener(_presenceChanged);
    for (final events in _events) {
      if (events.inkBegan == _began) events.inkBegan = null;
      if (events.inkEnded == _ended) events.inkEnded = null;
    }
    _timer?.cancel();
    _alive?.cancel();
  }
}
