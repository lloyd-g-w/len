import 'dart:ui';

import 'laser.dart';
import 'pointer_tool.dart';

/// Moves a [LaserTrail] with the pointer.
class LaserTool implements PointerTool {
  LaserTool(this.trail, {this._config});

  final LaserTrail trail;
  final LaserConfig Function()? _config;

  /// The last screen position added to the trail.
  Offset? _last;

  /// Samples closer than this (screen pixels) to the last recorded one only
  /// move the dot.
  static const double minGap = 1.5;

  @override
  void down(ToolPointer p) {
    if (_config case final config?) trail.config = config();
    _last = p.screen;
    trail.down(p.world, pressure: p.pressure);
  }

  @override
  void move(ToolPointer p) {
    final last = _last;
    final record = last == null || (p.screen - last).distance >= minGap;
    if (record) _last = p.screen;
    trail.move(p.world, record: record, pressure: p.pressure);
  }

  @override
  void up() => trail.up();

  @override
  void cancel() => trail.up();
}
