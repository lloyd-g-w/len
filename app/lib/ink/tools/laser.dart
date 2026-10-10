import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'pointer_tool.dart';

/// One sample of the laser trail; [time] is null until the next frame.
typedef LaserPoint = ({Offset world, int? time, bool startsSegment});

/// The laser pointer's fading trail. Never persisted: points simply expire
/// [lifetime] after they were drawn.
///
/// Time comes from frames ([tick], called by a ticker while the trail is
/// visible): a point is stamped with the time of the frame that first
/// shows it. Frame time is monotonic and needs no wall clock (and tests'
/// fake time drives it).
class LaserTrail extends ChangeNotifier {
  /// How long a point stays visible.
  static const Duration lifetime = Duration(milliseconds: 1000);

  final List<LaserPoint> _points = [];
  int _now = 0;

  List<LaserPoint> get points => _points;
  bool get isEmpty => _points.isEmpty;

  /// Time of the latest frame (ms).
  int get now => _now;

  /// Opacity (1 → 0) of a point drawn at [time], as of [now].
  static double fade(int? time, int now) =>
      time == null ? 1 : (1 - (now - time) / lifetime.inMilliseconds).clamp(0.0, 1.0);

  void add(Offset world, {bool startsSegment = false}) {
    _points.add((world: world, time: null, startsSegment: startsSegment || _points.isEmpty));
    notifyListeners();
  }

  /// Advances to frame time [nowMs]: stamps new points and drops expired
  /// ones. Call every frame while the trail is not empty.
  void tick(int nowMs) {
    _now = nowMs;
    final cutoff = nowMs - lifetime.inMilliseconds;
    for (var i = 0; i < _points.length; i++) {
      final p = _points[i];
      if (p.time == null) {
        _points[i] = (world: p.world, time: nowMs, startsSegment: p.startsSegment);
      }
    }
    final before = _points.length;
    _points.removeWhere((p) => p.time! <= cutoff);
    if (_points.isNotEmpty && _points.length != before) {
      final first = _points.first;
      _points[0] = (world: first.world, time: first.time, startsSegment: true);
    }
    notifyListeners();
  }

  void clear() {
    _points.clear();
    notifyListeners();
  }
}

/// Draws a [LaserTrail] while the pointer moves.
class LaserTool implements PointerTool {
  LaserTool(this.trail);

  final LaserTrail trail;

  @override
  void down(ToolPointer p) => trail.add(p.world, startsSegment: true);

  @override
  void move(ToolPointer p) => trail.add(p.world);

  @override
  void up() {}

  @override
  void cancel() {}
}
