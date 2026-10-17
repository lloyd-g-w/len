import 'dart:async';
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

  /// True when the live stroke is not free-hand ink: hold to snap made it
  /// a line or shape, or a tool draws it (no low-latency overlay then).
  bool straightened = false;

  /// The geometry of the shape the live stroke is (see [straightened]),
  /// committed with it.
  ShapeGeometry? shape;

  /// World position and radius of the eraser cursor, if visible.
  Offset? eraserCenter;
  double eraserRadius = 0;

  /// The hovering pen's preview, if visible: where its nib would land
  /// (world), its radius at medium pressure and its colour as previewed.
  Offset? penCenter;
  double penRadius = 0;
  Color penColor = const Color(0x00000000);

  /// Whether the live stroke shows only the part of its outline that is
  /// final, trailing the pen, as the stabiliser makes it: set for a mouse
  /// with its stabiliser on (applied before the outline, which then has
  /// none), so its ink does not settle at pen-up where it ended. Not
  /// while [straightened].
  bool trails = false;

  /// The provisional tip of a mouse stroke (world): where its ink runs on
  /// from the last point to the mouse, until the smoothing has the samples
  /// to place it for good (`MouseSmoother.tip`). Not part of the stroke;
  /// empty for a stylus or a finger, and once [points] change otherwise
  /// than by growing.
  List<Offset> get tip => _tip;
  List<Offset> _tip = const [];

  /// Shows [tip] (see [tip]); repaints without changing [revision].
  void showTip(List<Offset> tip) {
    if (tip.isEmpty && _tip.isEmpty) return;
    _tip = tip;
    notifyListeners();
  }

  List<StrokePoint> get points => _points;
  bool get isDrawing => _points.isNotEmpty;

  /// Changes whenever the live stroke changes, so painters can reuse the
  /// outline they built when only the eraser cursor or viewport moved.
  int get revision => _revision;

  /// Changes whenever the live stroke stops being the previous points plus
  /// more ([begin], [replaceAll]): an incremental outline builder must
  /// start again then.
  int get generation => _generation;
  int _generation = 0;

  void begin({
    required InkTool tool,
    required int color,
    required double width,
    StrokeStyle? style,
    bool trails = false,
  }) {
    this.trails = trails;
    this.tool = tool;
    this.color = color;
    this.width = width;
    this.style = style ?? StrokeStyle.defaultsFor(tool);
    straightened = false;
    shape = null;
    _points.clear();
    _tip = const [];
    _revision++;
    _generation++;
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
    _tip = const [];
    _points
      ..clear()
      ..addAll(points);
    _revision++;
    _generation++;
    notifyListeners();
  }

  /// Ends the live stroke and returns its points.
  List<StrokePoint> finish() {
    final points = List<StrokePoint>.of(_points);
    _points.clear();
    _tip = const [];
    straightened = false;
    shape = null;
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

  /// How long a stylus's hover cursors outlast its last event: Android
  /// reports no hover exit when the pen leaves range, while a pen in range
  /// streams hover events.
  static const Duration stylusHoverTimeout = Duration(milliseconds: 500);
  Timer? _hoverExpiry;

  /// Hides the eraser cursor and the pen's preview unless this is called
  /// again within [stylusHoverTimeout] (a stylus was seen again).
  void expireCursorsSoon() {
    _hoverExpiry?.cancel();
    _hoverExpiry = null;
    if (eraserCenter == null && penCenter == null) return;
    _hoverExpiry = Timer(stylusHoverTimeout, () {
      _hoverExpiry = null;
      showEraser(null, 0);
      showPen(null);
    });
  }

  /// Keeps the cursors: the pen touches (it can't have left range).
  void keepCursors() {
    _hoverExpiry?.cancel();
    _hoverExpiry = null;
  }

  @override
  void dispose() {
    _hoverExpiry?.cancel();
    super.dispose();
  }

  /// Moves (or hides, with a null [center]) the hovering pen's preview.
  void showPen(Offset? center, {double radius = 0, Color color = const Color(0x00000000)}) {
    if (center == penCenter && (center == null || (radius == penRadius && color == penColor))) {
      return;
    }
    penCenter = center;
    penRadius = radius;
    penColor = color;
    notifyListeners();
  }
}
