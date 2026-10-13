import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../domain/stroke.dart';
import '../render/stroke_renderer.dart';
import '../surface_model.dart';
import '../tool_settings.dart';
import '../viewport.dart';
import 'live_ink.dart';
import 'scribble_detector.dart';

/// Scribble to erase for `InkDrawing`: a ballpoint stroke that is a
/// scribble over ink ([ScribbleDetector]) erases the strokes under the
/// part that zigzags (one undo step) instead of becoming ink. Over
/// nothing, it is ink (shading, say); over a text box or image only, it is
/// dropped ([onMissed]: the scribble erases ink only).
///
/// Once the stroke is recognised as a scribble, the strokes it will erase
/// dim (fading in [fade]) while it goes on; they come back if the stroke
/// ends otherwise (cancelled, say). The preview is no edit: only the
/// erasing at pen-up is, one undo step.
class ScribbleErase {
  ScribbleErase({required this.viewport, required this.tools, required this.live});

  final ViewportController viewport;
  final ToolSettings tools;
  final LiveInk live;

  /// A scribble over a text box or image, with no ink under it, was
  /// dropped.
  void Function()? onMissed;

  /// How long the strokes about to go take to dim (`Motion.fast`).
  static const Duration fade = Duration(milliseconds: 100);

  /// How much of their ink dimmed strokes keep.
  static const double dimmed = 0.3;

  /// The preview follows the stroke every this many points.
  static const int _every = 4;

  final ScribbleDetector _detector = ScribbleDetector();
  SurfaceModel? _model;
  int _points = 0;

  /// The stroke snapped to a line or shape at some point: no scribble.
  bool _snapped = false;

  /// The zigzags the preview last followed (they only grow).
  List<(int, int)> _followed = const [];

  /// The strokes shown about to go (hidden from the ink, drawn dimmed).
  List<Stroke> _preview = const [];
  Set<String> _previewIds = const {};
  final Stopwatch _shown = Stopwatch();

  /// Whether strokes are shown about to go.
  bool get previewing => _preview.isNotEmpty;

  /// The strokes shown about to go.
  List<Stroke> get preview => _preview;

  /// A stroke started on [model] at [at] (screen).
  void begin(SurfaceModel model, Offset at, int timeMs) {
    end();
    _model = model;
    _points = 0;
    _snapped = false;
    _followed = const [];
    _detector.begin(at, timeMs);
  }

  /// The stroke went on to [at] (screen).
  void add(Offset at, int timeMs) {
    // Snapped to a shape, say: no scribble, even once the snap is undone
    // by the pen-up (`LiveInk.finish` clears the flag).
    _snapped = _snapped || live.straightened;
    if (!_enabled) return end();
    _detector.add(at, timeMs);
    if (++_points % _every == 0) _follow();
  }

  /// At pen-up: erases from [model] what the stroke's zigzags scribbled
  /// over, if it is a scribble over ink; returns whether it did (the
  /// stroke is then not kept). A scribble over a text box or image only
  /// is dropped too. A stroke [snapped] to a line or shape is no scribble.
  bool erase(SurfaceModel model, {bool snapped = false}) {
    end(); // What it dimmed counts again, and goes now.
    _snapped = _snapped || snapped;
    if (!_enabled || !_detector.isScribble) return false;
    final paths = _worldPaths;
    if (model.eraseScribbled(paths, _reach) == 0) {
      if (!model.scribbledOnElements(paths)) return false;
      onMissed?.call();
      return true;
    }
    unawaited(HapticFeedback.selectionClick());
    return true;
  }

  /// The zigzags, in world coordinates.
  List<List<Offset>> get _worldPaths => [
    for (final path in _detector.paths) [for (final p in path) viewport.toWorld(p)],
  ];

  /// The stroke ended (or was cancelled): dimmed strokes show again.
  void end() {
    final model = _model;
    if (model != null && previewing) {
      model
        ..setHidden(const {}, owner: this)
        ..setLifted(this, null);
    }
    _preview = const [];
    _previewIds = const {};
    _shown
      ..stop()
      ..reset();
  }

  /// Dims what the scribble so far will erase. Looks again only when the
  /// zigzags grew.
  void _follow() {
    final model = _model;
    final windows = _detector.windows;
    if (model == null || windows.isEmpty || _sameAs(windows)) return;
    _followed = List.of(windows);
    final going = model.scribbled(_worldPaths, _reach, preview: _previewIds);
    if (going.length == _preview.length) return; // It only ever grows.
    if (!previewing) _shown.start();
    _preview = going;
    _previewIds = {for (final s in going) s.id};
    model
      ..setHidden(_previewIds, owner: this)
      ..setLifted(this, _paint)
      ..liftedChanged(this);
  }

  /// Draws the strokes about to go, dimmed (in surface coordinates).
  void _paint(Canvas canvas) {
    if (!previewing) return;
    final t = math.min(1.0, _shown.elapsedMicroseconds / fade.inMicroseconds);
    var bounds = _preview.first.bounds;
    for (final s in _preview.skip(1)) {
      bounds = bounds.expandToInclude(s.bounds);
    }
    final alpha = 1 - (1 - dimmed) * t;
    canvas.saveLayer(bounds.inflate(1), Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    for (final s in _preview) {
      StrokeRenderer.draw(canvas, s);
    }
    canvas.restore();
    // Fading: paint again next frame (not during this paint).
    if (t < 1) {
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        if (previewing) _model?.liftedChanged(this);
      });
    }
  }

  bool _sameAs(List<(int, int)> windows) {
    if (windows.length != _followed.length) return false;
    for (var i = 0; i < windows.length; i++) {
      if (windows[i] != _followed[i]) return false;
    }
    return true;
  }

  /// Whether the live stroke may be a scribble to erase: the setting is on
  /// and it is plain ballpoint ink (never snapped to a shape).
  bool get _enabled =>
      tools.scribbleToErase && live.tool == InkTool.ballpoint && !_snapped && !live.straightened;

  /// How close (world) the scribble must pass to ink to erase it.
  double get _reach => math.max(live.width / 2, ScribbleDetector.reach / viewport.scale);
}
