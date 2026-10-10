import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'pointer_tool.dart';

/// One sample of the laser trail.
typedef LaserPoint = ({Offset world, int time, bool startsSegment});

/// The laser pointer's fading trail. Never persisted: points simply expire
/// [lifetime] after they were drawn.
class LaserTrail extends ChangeNotifier {
  LaserTrail({int Function()? nowMs}) : _now = nowMs ?? _frameClock;

  /// Frame time: monotonic, and advanced by tests' fake clock.
  static int _frameClock() => SchedulerBinding.instance.currentSystemFrameTimeStamp.inMilliseconds;

  final int Function() _now;

  /// How long a point stays visible.
  static const Duration lifetime = Duration(milliseconds: 1000);

  final List<LaserPoint> _points = [];

  List<LaserPoint> get points => _points;
  bool get isEmpty => _points.isEmpty;

  int get now => _now();

  /// Opacity (1 → 0) of a point drawn at [time], as of [now].
  static double fade(int time, int now) =>
      (1 - (now - time) / lifetime.inMilliseconds).clamp(0.0, 1.0);

  void add(Offset world, {bool startsSegment = false}) {
    _points.add((world: world, time: _now(), startsSegment: startsSegment || _points.isEmpty));
    notifyListeners();
  }

  /// Drops expired points; call every frame while the trail is visible.
  void tick() {
    final cutoff = _now() - lifetime.inMilliseconds;
    final before = _points.length;
    _points.removeWhere((p) => p.time <= cutoff);
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
