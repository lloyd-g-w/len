import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/paper.dart';
import '../../../ink/input/live_ink.dart';
import '../../../ink/input/pointer_navigation.dart';
import '../../../ink/surface_model.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/chrome_fade.dart';
import '../../../ui/floating_panel.dart';
import '../chrome/bar_button.dart';
import 'canvas_navigation.dart';
import 'minimap_geometry.dart';
import 'minimap_menu.dart';
import 'minimap_painter.dart';

part 'minimap_gestures.dart';
part 'minimap_viewport.dart';

/// The minimap's size for a canvas whose free area (beside the chrome) is
/// [free]: as wide as it within 1:1 and 16:10 (a tall map would leave
/// writing, which runs across, small), smaller on phones.
Size minimapSize(Size free, {bool phone = false}) {
  final long = phone ? CanvasMinimap.phoneSide : CanvasMinimap.side;
  final aspect = free.isEmpty ? 1.5 : (free.width / free.height).clamp(1.0, 1.6);
  return Size(long, long / aspect);
}

/// A small map of the whole canvas floating in a corner: soft blocks where
/// there is content and a frame for the visible area. Tap to glide there,
/// drag the frame (or anywhere) to move the view live; pinch, two fingers,
/// the wheel or the trackpad zoom and pan the map itself, never the canvas
/// (a fit button above it, or its menu, fits it again); long-press or
/// right-click for its menu.
///
/// The content comes from storage (populated chunks, read in the
/// background) and is re-read a moment after edits, never per frame. The
/// map fades away while the pen writes, and when there is nothing to show.
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
  });

  final CanvasNavigation navigation;
  final SurfaceModel model;

  /// The stroke being drawn: the map steps aside while it is.
  final LiveInk live;
  final Size size;

  /// The canvas background, mirrored by the map.
  final PaperColor paperColor;

  /// False hides the map (focus mode), keeping its content loaded.
  final bool visible;

  /// Turns the minimap off (its menu).
  final VoidCallback? onHide;

  /// Longer side of the map (on phones: [phoneSide]).
  static const double side = 176;
  static const double phoneSide = 120;

  /// The fit button's tooltip and the menu row that fits the map again.
  static const String fitLabel = 'Fit minimap';

  /// Delay after an edit before the content is re-read.
  static const Duration refreshDelay = Duration(milliseconds: 500);

  /// How long after the pen lifts the map comes back (not between strokes).
  static const Duration afterWriting = Duration(milliseconds: 1200);

  @override
  State<CanvasMinimap> createState() => _CanvasMinimapState();
}

class _CanvasMinimapState extends State<CanvasMinimap> with SingleTickerProviderStateMixin {
  MinimapContent _content = MinimapContent.empty;
  bool _loaded = false;
  StreamSubscription<SurfaceChange>? _changes;
  Timer? _refresh;
  int _request = 0;

  bool _writing = false;
  Timer? _back;

  /// The frame shown glides from [_from] to [_to] as [_glide] runs.
  late final AnimationController _glide = AnimationController(
    vsync: this,
    duration: Motion.medium,
    value: 1,
  );
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
      unawaited(_changes?.cancel());
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
    if (old.size != widget.size) {
      // Another shape: refit from scratch.
      _from = _to = _fit = _custom = null;
      _tracking = true;
      _onView();
    }
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _nav.viewport.removeListener(_onView);
    widget.live.removeListener(_onLive);
    _refresh?.cancel();
    _back?.cancel();
    _glide.dispose();
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
    unawaited(_load());
  }

  Future<void> _load() async {
    final request = ++_request;
    widget.model.flush(); // Storage must hold every edit.
    final density = await _nav.reader.chunkDensity(_nav.surfaceId);
    if (!mounted || request != _request) return;
    setState(() {
      _content = MinimapContent.fromDensity(density);
      _loaded = true;
    });
    _onView();
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

  double get _aspect => widget.size.width / widget.size.height;

  /// The world area shown now (between frames while it glides).
  Rect get _frame {
    final to = _to ?? _nav.visibleArea;
    final from = _from;
    if (from == null || _glide.value >= 1) return to;
    return Rect.lerp(from, to, Motion.standard.transform(_glide.value))!;
  }

  /// Keeps the map in step with the view and the content: refits when the
  /// view leaves the fit; a zoomed map stays put, nudged along while it
  /// follows the view, and fits again only once everything fits in it.
  void _onView({bool glide = false}) {
    if (_holding || _nav.viewport.size.isEmpty) return;
    final view = _nav.visibleArea;
    final fit = _fit = MinimapFrame.next(
      previous: _fit,
      content: _content.bounds,
      view: view,
      aspect: _aspect,
    );
    final custom = _custom;
    if (custom == null || custom.width >= fit.width) {
      _setCustom(null);
      return _moveTo(fit, glide: true);
    }
    var next = MinimapView.clampInto(custom, fit);
    if (_tracking) {
      next = MinimapView.follow(next, fit, view);
    } else {
      _tracking = MinimapView.tracks(next, view);
    }
    _custom = next;
    _moveTo(next, glide: glide);
  }

  /// Sets the map's own viewport, rebuilding when the fit button comes or
  /// goes (after the frame, when the view changed during a layout).
  void _setCustom(Rect? custom) {
    final changed = (custom == null) != (_custom == null);
    _custom = custom;
    if (!changed) return;
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      return setState(() {});
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.visible && !_writing && _loaded && !_content.isEmpty;
    // A window onto the paper: the panel's hairline and shadow, no rim.
    final map = FloatingPanel(
      padding: EdgeInsets.zero,
      child: _MinimapGestures(
        state: this,
        // It repaints with every frame of a pan: alone, not the editor.
        child: RepaintBoundary(
          child: CustomPaint(
            size: widget.size,
            painter: MinimapPainter(
              content: _content,
              frame: () => _frame,
              view: () => _nav.visibleArea,
              colors: _colors(Theme.of(context).colorScheme),
              blocks: _blocks,
              repaint: Listenable.merge([_nav.viewport, _glide, _moved]),
            ),
          ),
        ),
      ),
    );
    return ChromeFade(
      visible: shown,
      edge: const Offset(0, 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Above the map while it is zoomed or panned: fit it again.
          ChromeFade(
            visible: _custom != null,
            edge: const Offset(0, 1),
            child: FloatingPanel(
              radius: Radii.pill,
              padding: EdgeInsets.zero,
              child: BarButton(
                icon: Symbols.fit_screen_rounded,
                tooltip: CanvasMinimap.fitLabel,
                onPressed: _custom == null ? null : _fitMap,
              ),
            ),
          ),
          const SizedBox(height: Gaps.xs),
          map,
        ],
      ),
    );
  }

  MinimapColors _colors(ColorScheme scheme) {
    final paper = widget.paperColor;
    // The frame sits on the paper: the accent for the paper's brightness.
    final view = paper.isDark == (scheme.brightness == Brightness.dark)
        ? scheme.primary
        : scheme.inversePrimary;
    return MinimapColors(paper: paper.paper, ink: paper.text, view: view);
  }
}
