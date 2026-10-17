import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../domain/stroke.dart';
import '../sync/live_rooms.dart';
import '../sync/remote_changes.dart';
import 'render/live_stroke.dart';
import 'render/stroke_renderer.dart';

/// Strokes other devices in a notebook's room are writing right now (live
/// ink, docs/SYNC_PROTOCOL.md "Room data"), drawn as provisional ink until
/// the records of the strokes it became arrive and show ([landed]), the
/// writer says it ended without any, leaves the room (or this device's connection drops), or it
/// goes quiet.
class RemoteInk extends ChangeNotifier {
  RemoteInk(this.rooms, {required this.room}) {
    _subscription = rooms.messages.where((m) => m.room == room).listen(receive);
    rooms.addListener(_membersChanged);
  }

  /// The rooms this device is in: their messages and presence.
  final LiveRooms rooms;

  /// The room (notebook) whose ink this is.
  final String room;

  /// How long a stroke being written may go unheard before it is dropped
  /// (its writer left), and how long an ended one waits for its record.
  static const silence = Duration(seconds: 3);
  static const afterEnd = Duration(seconds: 2);

  late final StreamSubscription<RoomMessage> _subscription;
  final Map<String, _Writing> _writing = {};

  /// Strokes that arrived on surfaces with remote ink, with when (in
  /// sweeps): a record can overtake its stroke's `end`.
  final Map<String, int> _landed = {};
  Timer? _sweep;
  int _now = 0; // Sweeps since the first stroke (seconds / 2).

  /// Whether any remote ink is shown.
  bool get isEmpty => _writing.isEmpty;

  /// The strokes being written on [surfaceId], in the order they began.
  List<Stroke> strokesOn(String surfaceId) => [
    for (final w in _writing.values)
      if (w.surface == surfaceId && w.points.length > 1) w.stroke,
  ];

  /// The outlines of the strokes being written on [surfaceId] with their
  /// paints, in the order they began: built as their points come (what a
  /// message adds, as the writer's own live ink is), not whole again.
  List<(Path, Paint)> outlinesOn(String surfaceId) => [
    for (final w in _writing.values)
      if (w.surface == surfaceId && w.points.length > 1)
        (w.outline, StrokeRenderer.paintFor(w.color, w.style)),
  ];

  /// The surfaces showing remote ink now.
  Iterable<String> get surfaces => _writing.values.map((w) => w.surface).toSet();

  /// Whether surface [surface] shows stroke [strokeId] now that its record
  /// arrived; false while the surface reloads whole (many changes, a
  /// selection in the way): the provisional ink stays until it does
  /// (call [recheck] when it may). Unset: always.
  bool Function(String surface, String strokeId)? shows;

  /// The surfaces whose remote ink waits for their reload ([shows]).
  Set<String> get reloading => {
    for (final w in _writing.values)
      if (w.ended && w.waiting.isEmpty) w.surface,
  };

  /// Takes a message of the room.
  void receive(RoomMessage message) {
    final data = message.data;
    if (message.room != room || data['k'] != 'ink' || data['s'] is! String) return;
    final key = '${message.from}/${data['s']}';
    if (data['end'] == true) {
      final w = _writing[key];
      if (w == null) return;
      final strokes = data['strokes'];
      final ids = strokes is List ? strokes.whereType<String>().toSet() : const <String>{};
      w
        ..ended = true
        ..heard = _now
        ..waiting.addAll(ids.where((id) => !_landed.containsKey(id)))
        ..arrived.addAll(ids.where(_landed.containsKey));
      if (ids.isEmpty || _done(w)) {
        _writing.remove(key);
        notifyListeners();
      }
      return;
    }
    final w = _writing[key] ?? _begin(key, message.from, data);
    if (w == null) return;
    final from = data['from'];
    final p = data['p'];
    if (from is! int || p is! List || from > w.points.length) return; // Missed some: wait.
    if (from < w.points.length) {
      w.points.removeRange(from, w.points.length);
      w.builder = null; // Replaced: its outline starts again.
    }
    for (var i = 0; i + 2 < p.length; i += 3) {
      final (x, y, pressure) = (p[i], p[i + 1], p[i + 2]);
      if (x is! num || y is! num || pressure is! num) return;
      w.points.add(StrokePoint(x.toDouble(), y.toDouble(), pressure.toDouble()));
    }
    w
      ..heard = _now
      ..revision += 1;
    _sweep ??= Timer.periodic(const Duration(milliseconds: 500), (_) => _expire());
    notifyListeners();
  }

  _Writing? _begin(String key, String from, Map<String, Object?> data) {
    final surface = data['page'];
    final tool = InkTool.values.asNameMap()[data['tool']];
    final color = data['color'];
    final width = data['width'];
    if (surface is! String || tool == null || color is! int || width is! num) return null;
    StrokeStyle style;
    try {
      style = StrokeStyle.fromJson(data['style']);
    } on Object {
      style = StrokeStyle.defaultsFor(tool);
    }
    return _writing[key] = _Writing(from, surface, tool, color, width.toDouble(), style)
      ..heard = _now;
  }

  /// A sync brought [changes]: remote ink whose strokes arrived goes (they
  /// are drawn as committed ink now), once its surface [shows] them.
  void landed(RemoteChanges changes) {
    if (_writing.isEmpty) return;
    for (final surface in surfaces) {
      for (final id in changes.itemsOf(surface) ?? const <String>{}) {
        _landed[id] = _now;
      }
    }
    for (final w in _writing.values) {
      if (!w.ended || !changes.strokeSurfaces.contains(w.surface)) continue;
      final items = changes.itemsOf(w.surface); // Null: reloaded whole.
      final came = items == null ? {...w.waiting} : w.waiting.intersection(items);
      if (came.isEmpty) continue;
      w
        ..waiting.removeAll(came)
        ..arrived.addAll(came)
        ..heard = _now; // Waits for a reload afresh.
    }
    recheck();
  }

  /// Drops the remote ink whose strokes are all shown now ([shows]).
  void recheck() {
    final before = _writing.length;
    _writing.removeWhere((_, w) => w.ended && _done(w));
    _changed(before);
  }

  /// Whether every stroke [w] became arrived and is shown.
  bool _done(_Writing w) =>
      w.waiting.isEmpty && w.arrived.every((id) => shows?.call(w.surface, id) ?? true);

  void _expire() {
    _now++;
    final before = _writing.length;
    final quiet = silence.inMilliseconds ~/ 500;
    final waited = afterEnd.inMilliseconds ~/ 500;
    _writing.removeWhere((_, w) => _now - w.heard >= (w.ended ? waited : quiet));
    _landed.removeWhere((_, at) => _now - at >= waited);
    _changed(before);
  }

  /// Presence changed: ink of writers no longer in the room goes (they
  /// left, or this device's connection dropped and nobody is known there).
  void _membersChanged() {
    if (_writing.isEmpty) return;
    final members = {for (final m in rooms.othersIn(room)) m.connection};
    final before = _writing.length;
    _writing.removeWhere((_, w) => !members.contains(w.from));
    _changed(before);
  }

  /// Ends the sweeps once nothing is shown; repaints if [before] changed.
  void _changed(int before) {
    if (_writing.isEmpty) {
      _landed.clear();
      _sweep?.cancel();
      _sweep = null;
    }
    if (_writing.length != before) notifyListeners();
  }

  @override
  void dispose() {
    rooms.removeListener(_membersChanged);
    unawaited(_subscription.cancel());
    _sweep?.cancel();
    super.dispose();
  }
}

/// One stroke another device is writing.
class _Writing {
  _Writing(this.from, this.surface, this.tool, this.color, this.width, this.style);

  /// The writer's connection.
  final String from;
  final String surface;
  final InkTool tool;
  final int color;
  final double width;
  final StrokeStyle style;
  final List<StrokePoint> points = [];

  /// Bumped with every change ([stroke] is rebuilt then).
  int revision = 0;

  /// When it was last heard of (in sweeps), and whether it ended.
  int heard = 0;
  bool ended = false;

  /// Once [ended]: the strokes it became whose records did not arrive yet,
  /// and those that did.
  final Set<String> waiting = {};
  final Set<String> arrived = {};

  Stroke? _stroke;
  int _built = -1;

  /// The outline as of [revision], and the builder extending it.
  LiveStrokeBuilder? builder;
  Path? _outline;
  int _outlined = -1;

  Path get outline {
    if (_outlined != revision) {
      _outlined = revision;
      final built = LiveStrokeBuilder.build(builder, points, width: width, style: style);
      builder = built.builder;
      _outline = built.path.combined;
    }
    return _outline!;
  }

  Stroke get stroke {
    if (_built != revision) {
      _built = revision;
      _stroke = Stroke(
        id: 'remote-${identityHashCode(this)}-$revision',
        surfaceId: surface,
        tool: tool,
        color: color,
        width: width,
        style: style,
        points: List.of(points),
        createdAt: 0,
      );
    }
    return _stroke!;
  }
}
