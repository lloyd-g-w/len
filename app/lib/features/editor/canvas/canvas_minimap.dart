import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/paper.dart';
import '../../../domain/preferences.dart';
import '../../../ink/input/live_ink.dart';
import '../../../ink/input/pointer_navigation.dart';
import '../../../ink/surface_model.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/chrome_fade.dart';
import '../../../ui/floating_panel.dart';
import '../chrome/bar_button.dart';
import 'canvas_navigation.dart';
import 'minimap_controls.dart';
import 'minimap_geometry.dart';
import 'minimap_menu.dart';
import 'minimap_painter.dart';
import 'minimap_raster.dart';
import 'minimap_sketch.dart';

part 'minimap_gestures.dart';
part 'minimap_layout.dart';
part 'minimap_viewport.dart';

/// The minimap's size for a canvas whose free area (beside the chrome) is
/// [free]: as wide as it within 1:1 and 16:10 (a tall map would leave
/// writing, which runs across, small), its longer side by [scale]
/// (by default small on phones, medium elsewhere) and never more than
/// half the free width.
Size minimapSize(Size free, {bool phone = false, MinimapScale? scale}) {
  final chosen = scale ?? CanvasMinimap.defaultScale(phone: phone);
  var long = CanvasMinimap.sides[chosen]!;
  if (!free.isEmpty) long = math.min(long, math.max(CanvasMinimap.minSide, free.width / 2));
  final aspect = free.isEmpty ? 1.5 : (free.width / free.height).clamp(1.0, 1.6);
  return Size(long, long / aspect);
}

/// A small map of the whole canvas floating in a corner: a miniature of
/// the content in its colours, the visible area clear and framed, the rest
/// veiled. One pointer moves the canvas's view: tap to glide there (twice
/// to zoom in there), drag the frame (or anywhere) to move the view live,
/// drag a corner of the frame to zoom. Pinch, two fingers, the wheel or
/// the trackpad zoom and pan the map itself, never the canvas (a fit
/// button above it, or its menu, fits it again). Its buttons zoom the
/// canvas out and in, fit all the content and fold the map into a button
/// (remembered); long-press or right-click for its menu (fit, size, fold,
/// hide).
///
/// The content comes from storage ([MinimapSketch]: only chunks whose
/// digests changed are read again, a moment after edits, in the
/// background) and is drawn into an image or two ([MinimapRaster]) when it
/// or the area shown changes, never per frame. The map fades away while
/// the pen writes, and when there is nothing to show.
class CanvasMinimap extends StatefulWidget {
  const CanvasMinimap({
    super.key,
    required this.navigation,
    required this.model,
    required this.live,
    required this.size,
    this.paperColor = PaperColor.white,
    this.visible = true,
    this.onHide,
    this.collapsed = false,
    this.onCollapsed,
    this.scale,
    this.onScale,
  });

  final CanvasNavigation navigation;
  final SurfaceModel model;

  /// The stroke being drawn: the map steps aside while it is.
  final LiveInk live;

  /// The map's own size (its buttons go below it).
  final Size size;

  /// The canvas background, mirrored by the map.
  final PaperColor paperColor;

  /// False hides the map (focus mode), keeping its content loaded.
  final bool visible;

  /// Turns the minimap off (its menu).
  final VoidCallback? onHide;

  /// Whether the map is folded into its button; [onCollapsed] remembers a
  /// change.
  final bool collapsed;
  final ValueChanged<bool>? onCollapsed;

  /// The size chosen in its menu (null: by device); [onScale] picks one.
  final MinimapScale? scale;
  final ValueChanged<MinimapScale>? onScale;

  /// Longer side of the map by size.
  static const Map<MinimapScale, double> sides = {
    MinimapScale.small: 144,
    MinimapScale.medium: 192,
    MinimapScale.large: 264,
  };

  /// The map never gets narrower than this when the screen is.
  static const double minSide = 120;

  /// The size on phones, else.
  static MinimapScale defaultScale({required bool phone}) =>
      phone ? MinimapScale.small : MinimapScale.medium;

  /// The fit button's tooltip and the menu row that fits the map again.
  static const String fitLabel = 'Fit minimap';

  /// Delay after an edit before the content is re-read.
  static const Duration refreshDelay = Duration(milliseconds: 500);

  /// How long after the pen lifts the map comes back (not between strokes).
  static const Duration afterWriting = Duration(milliseconds: 1200);

  /// The miniature is drawn again at most this often.
  static const Duration rasterDelay = Duration(milliseconds: 80);

  @override
  State<CanvasMinimap> createState() => _CanvasMinimapState();
}

class _CanvasMinimapState extends State<CanvasMinimap> with SingleTickerProviderStateMixin {
  MinimapSketch _sketch = MinimapSketch();
  late MinimapRaster _raster = MinimapRaster(images: widget.model.images);

  /// Ticks when a new miniature is ready (the painter repaints).
  final ValueNotifier<int> _painted = ValueNotifier(0);
  bool _loaded = false;
  StreamSubscription<SurfaceChange>? _changes;
  StreamSubscription<String>? _images;
  Timer? _refresh;
  Timer? _rasterTimer;
  bool _updating = false;
  bool _again = false;
  bool _rendering = false;
  double _dpr = 1;

  bool _writing = false;
  Timer? _back;
  late bool _collapsed = widget.collapsed;

  /// The frame shown glides from [_from] to [_to] as [_glide] runs.
  late final AnimationController _glide = AnimationController(
    vsync: this,
    duration: Motion.medium,
    value: 1,
  )..addStatusListener(_onGlide);
  Rect? _from;
  Rect? _to;

  /// The world area that fits the content and the view ([MinimapFrame]).
  Rect? _fit;

  /// The map's own viewport once zoomed or panned (null: it fits [_fit]).
  Rect? _custom;

  /// Whether the zoomed map follows the view (its centre was on the map).
  bool _tracking = true;

  /// Set while a gesture is on the map: the view moving doesn't move it.
  bool _holding = false;

  /// Repaints the map when it moves at once (gestures, following).
  final ValueNotifier<int> _moved = ValueNotifier(0);

  /// The blocks drawn while there is no miniature.
  final MinimapBlocks _blocks = MinimapBlocks();

  CanvasNavigation get _nav => widget.navigation;

  @override
  void initState() {
    super.initState();
    _attach();
    _nav.viewport.addListener(_onView);
    widget.live.addListener(_onLive);
  }

  @override
  void didUpdateWidget(CanvasMinimap old) {
    super.didUpdateWidget(old);
    if (old.model != widget.model) {
      _detach();
      _sketch = MinimapSketch();
      _raster = MinimapRaster(images: widget.model.images);
      _attach();
    }
    if (old.navigation != widget.navigation) {
      old.navigation.viewport.removeListener(_onView);
      _nav.viewport.addListener(_onView);
    }
    if (old.live != widget.live) {
      old.live.removeListener(_onLive);
      widget.live.addListener(_onLive);
    }
    if (old.collapsed != widget.collapsed) _collapsed = widget.collapsed;
    if (old.size != widget.size) {
      // Another shape: refit from scratch.
      _from = _to = _fit = _custom = null;
      _tracking = true;
      _onView();
      _scheduleRaster();
    }
  }

  @override
  void dispose() {
    _detach();
    _nav.viewport.removeListener(_onView);
    widget.live.removeListener(_onLive);
    _back?.cancel();
    _rasterTimer?.cancel();
    _glide.dispose();
    _painted.dispose();
    _moved.dispose();
    _blocks.dispose();
    super.dispose();
  }

  void _attach() {
    _changes = widget.model.changes.listen((change) {
      // Loading and evicting only move stored content in and out of
      // memory: nothing new to map.
      if (!change.altersContent) return;
      _refresh?.cancel();
      _refresh = Timer(CanvasMinimap.refreshDelay, () => unawaited(_load()));
    });
    _images = widget.model.images?.changes.listen((_) {
      _sketch.imagesChanged();
      _scheduleRaster();
    });
    unawaited(_load());
  }

  void _detach() {
    unawaited(_changes?.cancel());
    unawaited(_images?.cancel());
    _refresh?.cancel();
    _raster.dispose();
  }

  /// Brings the content up to date with storage (one update at a time).
  Future<void> _load() async {
    if (_updating) {
      _again = true;
      return;
    }
    _updating = true;
    final sketch = _sketch;
    var changed = false;
    try {
      widget.model.flush(); // Storage must hold every edit.
      changed = await sketch.update(_nav.reader, _nav.surfaceId, progress: _scheduleRaster);
    } finally {
      _updating = false;
    }
    if (!mounted || sketch != _sketch) return;
    if (!_loaded || changed) setState(() => _loaded = true);
    if (changed) {
      _onView();
      _scheduleRaster();
    }
    if (_again) {
      _again = false;
      unawaited(_load());
    }
  }

  void _onLive() {
    final drawing = widget.live.isDrawing;
    if (drawing) {
      _back?.cancel();
      _back = null;
      if (!_writing) setState(() => _writing = true);
    } else if (_writing && _back == null) {
      _back = Timer(CanvasMinimap.afterWriting, () {
        _back = null;
        if (mounted) setState(() => _writing = false);
      });
    }
  }

  void _rebuild() => setState(() {});

  void _setCollapsed(bool collapsed) {
    if (collapsed == _collapsed) return;
    setState(() => _collapsed = collapsed);
    widget.onCollapsed?.call(collapsed);
  }

  @override
  Widget build(BuildContext context) {
    _dpr = MediaQuery.devicePixelRatioOf(context);
    final shown = widget.visible && !_writing && _loaded && !_sketch.isEmpty;
    return ChromeFade(
      visible: shown,
      edge: const Offset(0, 1),
      child: _collapsed ? _folded() : _unfolded(context),
    );
  }
}
