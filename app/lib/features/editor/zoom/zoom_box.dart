import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../data/app_preferences.dart';
import '../../../ink/input/stylus_buttons.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../editor_session.dart';
import 'zoom_box_grip.dart';
import 'zoom_box_menu.dart';
import 'zoom_box_paper.dart';
import 'zoom_box_rail.dart';
import 'zoom_window.dart';

/// The zoom window's box, docked at the bottom of the editor: the frame's
/// part of the page, magnified, to write in, and a rail with ✕ (close) and
/// ↵ (next line). Pointers go to the window's own input controller, so
/// ink is made exactly as on the page, at the box's zoom.
class ZoomBox extends StatefulWidget {
  const ZoomBox({
    super.key,
    required this.session,
    this.padding = EdgeInsets.zero,
    this.atTop = false,
  });

  final EditorSession session;

  /// Whether the box docks under the top chrome (left-handed writing):
  /// its edge to the page, with the grip, is then its bottom.
  final bool atTop;

  /// Room kept clear at the sides (a phone's notch, held sideways).
  final EdgeInsets padding;

  /// The lowest box, and the least of the page kept in view above it.
  static const double least = 112, pageRoom = 120;

  /// The box's height in an editor with [free] pixels of height between
  /// its top and bottom chrome: the height [chosen] by dragging its top
  /// edge, else about a third; always leaving the page room.
  static double heightFor(double free, {double? chosen}) {
    const share = 0.36, most = 300.0;
    final room = math.max(0.0, free - pageRoom);
    if (chosen != null) return chosen.clamp(math.min(least, room), room);
    return (free * share).clamp(least, most).clamp(0.0, math.min(room, most));
  }

  @override
  State<ZoomBox> createState() => _ZoomBoxState();
}

class _ZoomBoxState extends State<ZoomBox> {
  ZoomWindow get _zoom => widget.session.zoomWindow;
  ToolSettings get _tools => widget.session.tools;

  /// The contact writing in the box, and the ink it made (surface units).
  int? _pointer;
  bool _inking = false;
  Rect? _ink;
  final Set<int> _ignored = {};

  /// A finger or the mouse dragging the top edge.
  final BoxHeightDrag _sizing = BoxHeightDrag();

  /// Whether tickers run here: a parked split pane runs none, and neither
  /// does the frame's glide.
  ValueListenable<TickerModeData>? _tickerMode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mode = TickerMode.getValuesNotifier(context);
    if (mode != _tickerMode) {
      _tickerMode?.removeListener(_onTickerMode);
      _tickerMode = mode..addListener(_onTickerMode);
    }
    _onTickerMode();
  }

  void _onTickerMode() => _zoom.ticking = _tickerMode?.value.enabled ?? true;

  AppPreferences get _preferences => widget.session.services.preferences;

  @override
  void initState() {
    super.initState();
    _preferences.addListener(_onPreferences);
  }

  /// The direction was turned over (here, or in the other pane's box): the
  /// line starts again from where the frame is, in the new direction.
  void _onPreferences() {
    if (_preferences.zoomWritesRightToLeft != _zoom.rightToLeft) _zoom.directionChanged();
  }

  @override
  void dispose() {
    _preferences.removeListener(_onPreferences);
    _tickerMode?.removeListener(_onTickerMode);
    _zoom.ticking = true;
    super.dispose();
  }

  void _onLayout(Size size) {
    if (size == _zoom.box) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _zoom.setBox(size);
    });
  }

  /// The box writes with the pen and highlighter and erases; the lasso,
  /// shapes, text and laser work on the page.
  bool _accepts(PointerDownEvent e) {
    final input = _zoom.input;
    if (input == null) return false;
    final route = routeStylus(e.kind, e.buttons, input.penButtonAction);
    if (route == StylusRoute.lasso) return false;
    if (route == StylusRoute.eraser) return true;
    return switch (_tools.tool) {
      EditorTool.pen || EditorTool.highlighter || EditorTool.eraser => true,
      _ => false,
    };
  }

  bool _inks(PointerDownEvent e) =>
      _tools.tool != EditorTool.eraser &&
      routeStylus(e.kind, e.buttons, _zoom.input!.penButtonAction) == StylusRoute.tool;

  /// Tells the page view where the pen is: a hand writing in the box rests
  /// on the page.
  void _stylus(PointerEvent e) {
    if (isStylusKind(e.kind)) widget.session.input.stylusElsewhere(e);
  }

  void _down(PointerDownEvent e) {
    _stylus(e);
    final height = context.size?.height ?? 0;
    if (_pointer == null &&
        _sizing.start(
          e,
          reach: ZoomBoxGrip.reach(context),
          paper: _zoom.box.height,
          height: height,
          atBottom: widget.atTop,
        )) {
      return;
    }
    if (_sizing.active || !_accepts(e)) {
      _ignored.add(e.pointer);
      return;
    }
    final first = _pointer == null;
    if (first || isStylusKind(e.kind)) {
      _pointer = e.pointer;
      _inking = _inks(e);
      _ink = null;
      _zoom.penDown();
    }
    _zoom.input!.handleDown(e);
    _note(e);
  }

  void _move(PointerMoveEvent e) {
    _stylus(e);
    if (_sizing.move(e) case final height?) return _resize(height);
    if (_ignored.contains(e.pointer)) return;
    _zoom.input?.handleMove(e);
    _note(e);
  }

  void _note(PointerEvent e) {
    if (e.pointer != _pointer || !_inking) return;
    final at = _zoom.view.toWorld(e.localPosition);
    final dot = Rect.fromCenter(center: at, width: 0, height: 0);
    _ink = _ink?.expandToInclude(dot) ?? dot;
  }

  void _up(PointerUpEvent e) {
    _stylus(e);
    if (_sizing.end(e)) return _settleHeight();
    if (_ignored.remove(e.pointer)) return;
    final input = _zoom.input;
    if (input == null) return;
    // A finger that turned into a pan or pinch wrote nothing.
    final navigated = input.navigates(e.pointer);
    input.handleUp(e);
    if (e.pointer != _pointer) return;
    _pointer = null;
    // A scribble that erased (or a bounce) left no ink to move on from.
    _zoom.penUp(_inking && !navigated && input.inked ? _ink : null);
  }

  void _cancel(PointerCancelEvent e) {
    _stylus(e);
    if (_sizing.end(e)) return _settleHeight();
    if (_ignored.remove(e.pointer)) return;
    _zoom.input?.handleCancel(e);
    if (e.pointer != _pointer) return;
    _pointer = null;
    _zoom.penUp(null);
  }

  /// Asks the editor for a box [height] high (it keeps the page room).
  void _resize(double height) => _zoom.boxHeight.value = height;

  /// Keeps the height the editor gave the box, so the next drag starts
  /// from it (not from a height past the limits).
  void _settleHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = mounted ? context.size : null;
      if (size != null) _zoom.boxHeight.value = size.height;
    });
  }

  void _step(double by) {
    _resize((context.size?.height ?? 0) + by);
    _settleHeight();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    _zoom.reducedMotion = Motion.reduced(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Surfaces.chrome(scheme),
        border: widget.atTop
            ? Border(bottom: Surfaces.chromeEdge(scheme))
            : Border(top: Surfaces.chromeEdge(scheme)),
      ),
      child: Padding(
        padding: widget.padding.copyWith(
          top: widget.atTop ? 0 : Hairline.width,
          bottom: widget.atTop ? Hairline.width : 0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _onLayout(constraints.biggest);
                  return ClipRect(child: _paper(context));
                },
              ),
            ),
            ListenableBuilder(
              listenable: _zoom,
              builder: (context, _) => ZoomBoxRail(
                onClose: _zoom.close,
                onNewLine: _zoom.newLine,
                menu: () => zoomBoxMenu(widget.session),
                onMenu: (choice) => onZoomBoxMenu(widget.session, choice),
                rightToLeft: _zoom.rightToLeft,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paper(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      onExit: (_) => _zoom.input?.handleExit(),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        onPointerHover: (e) {
          _stylus(e);
          _zoom.input?.handleHover(e);
        },
        onPointerSignal: (e) {
          final input = _zoom.input;
          if (input == null) return;
          GestureBinding.instance.pointerSignalResolver.register(e, input.handleSignal);
        },
        onPointerPanZoomStart: (e) => _zoom.input?.handlePanZoomStart(e),
        onPointerPanZoomUpdate: (e) => _zoom.input?.handlePanZoomUpdate(e),
        onPointerPanZoomEnd: (e) => _zoom.input?.handlePanZoomEnd(e),
        child: ZoomBoxPaper(session: widget.session, gripAtBottom: widget.atTop, onStep: _step),
      ),
    );
  }
}
