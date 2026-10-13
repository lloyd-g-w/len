import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../../domain/stroke.dart';
import '../surface_model.dart';
import '../tool_settings.dart';
import '../viewport.dart';
import 'live_ink.dart';
import 'scribble_detector.dart';

/// Scribble to erase for `InkDrawing`: a ballpoint stroke that is a
/// scribble over ink ([ScribbleDetector]) erases the strokes under it (one
/// undo step) instead of becoming ink. Over nothing, it is ink (shading,
/// say).
class ScribbleErase {
  ScribbleErase({required this.viewport, required this.tools, required this.live});

  final ViewportController viewport;
  final ToolSettings tools;
  final LiveInk live;

  final ScribbleDetector _detector = ScribbleDetector();

  /// A stroke started at [at] (screen).
  void begin(Offset at, int timeMs) => _detector.begin(at, timeMs);

  /// The stroke went on to [at] (screen).
  void add(Offset at, int timeMs) => _detector.add(at, timeMs);

  /// At pen-up: erases from [model] what the stroke of [points] (world)
  /// scribbled over, if it is a scribble over ink; returns whether it did
  /// (the stroke is then not kept).
  bool erase(SurfaceModel model, List<StrokePoint> points) {
    if (!_enabled || !_detector.isScribble) return false;
    if (model.eraseScribbled([for (final p in points) p.offset], _reach) == 0) return false;
    unawaited(HapticFeedback.selectionClick());
    return true;
  }

  /// Whether the live stroke may be a scribble to erase: the setting is on
  /// and it is plain ballpoint ink (not snapped to a shape).
  bool get _enabled =>
      tools.scribbleToErase && live.tool == InkTool.ballpoint && !live.straightened;

  /// How close (world) the scribble must pass to ink to erase it.
  double get _reach => math.max(live.width / 2, ScribbleDetector.reach / viewport.scale);
}
