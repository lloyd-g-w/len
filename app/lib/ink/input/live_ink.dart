import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../domain/stroke.dart';

/// Transient, rapidly changing ink state: the stroke being drawn right now
/// and the eraser cursor. Kept separate from [SurfaceModel] so that only the
/// lightweight live layer repaints on every pointer move.
class LiveInk extends ChangeNotifier {
  final List<StrokePoint> _points = [];
  int _revision = 0;

  InkTool tool = InkTool.ballpoint;
  int color = 0xFF000000;
  double width = 2;
  StrokeStyle style = const StrokeStyle();

  /// True once "hold to straighten" has snapped the live stroke to a line.
  bool straightened = false;

  /// World position and radius of the eraser cursor, if visible.
  Offset? eraserCenter;
  double eraserRadius = 0;

  List<StrokePoint> get points => _points;
  bool get isDrawing => _points.isNotEmpty;

  /// Changes whenever the live stroke changes, so painters can reuse the
  /// outline they built when only the eraser cursor or viewport moved.
  int get revision => _revision;

  void begin({
    required InkTool tool,
    required int color,
    required double width,
    StrokeStyle? style,
  }) {
    this.tool = tool;
    this.color = color;
    this.width = width;
    this.style = style ?? StrokeStyle.defaultsFor(tool);
    straightened = false;
    _points.clear();
    _revision++;
    notifyListeners();
  }

  void add(StrokePoint point) {
    _points.add(point);
    _revision++;
    notifyListeners();
  }

  /// Adds several points at once (one notification).
  void addAll(List<StrokePoint> points) {
    if (points.isEmpty) return;
    _points.addAll(points);
    _revision++;
    notifyListeners();
  }

  /// Replaces every point of the live stroke (e.g. when it is straightened).
  void replaceAll(List<StrokePoint> points) {
    _points
      ..clear()
      ..addAll(points);
    _revision++;
    notifyListeners();
  }

  /// Ends the live stroke and returns its points.
  List<StrokePoint> finish() {
    final points = List<StrokePoint>.of(_points);
    _points.clear();
    straightened = false;
    _revision++;
    notifyListeners();
    return points;
  }

  /// Moves (or hides, with a null [center]) the eraser cursor. Hover events
  /// call this constantly, so unchanged state does not trigger a repaint.
  void showEraser(Offset? center, double radius) {
    if (center == eraserCenter && (center == null || radius == eraserRadius)) return;
    eraserCenter = center;
    eraserRadius = radius;
    notifyListeners();
  }
}
