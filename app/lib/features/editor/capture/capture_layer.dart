import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import 'area_capture.dart';
import 'area_capturer.dart';
import 'capture_result_bar.dart';

/// The area capture's layer over the whole app: it takes every pointer
/// (nothing draws, scrolls or opens meanwhile) and shows the hint "Drag
/// over the area to capture". A drag on the surface marks the area;
/// lifting captures it ([capture]) and shows the [CaptureResultBar] by
/// it. A press elsewhere (chrome, menus) or Escape ends it, as does a tap
/// beside the bar once captured; a palm near the pen is ignored.
class CaptureLayer extends StatefulWidget {
  const CaptureLayer({
    super.key,
    required this.free,
    required this.onSurface,
    required this.isPalm,
    required this.capture,
    required this.onSave,
    required this.onInsert,
    required this.onDone,
    this.initial,
    this.result,
  });

  /// The part of the surface clear of chrome (global), where areas are
  /// dragged.
  final Rect? Function() free;

  /// Whether the surface is what shows at a point (global): no chrome
  /// over it.
  final bool Function(Offset global) onSurface;
  final bool Function(PointerDownEvent down) isPalm;

  /// Captures the area dragged (global); null when nothing is there.
  final Future<CaptureResult>? Function(Rect global) capture;
  final ValueChanged<CapturedArea> onSave;
  final ValueChanged<CapturedArea> onInsert;
  final VoidCallback onDone;

  /// An area captured already (global), and its capture.
  final Rect? initial;
  final Future<CaptureResult>? result;

  static const String hint = 'Drag over the area to capture';

  /// Shorter drags (screen pixels, either way) capture nothing.
  static const double minDrag = 8;

  @override
  State<CaptureLayer> createState() => _CaptureLayerState();
}

class _CaptureLayerState extends State<CaptureLayer> {
  /// The pointer dragging, and where it went down.
  int? _pointer;
  Offset? _from;

  /// The area marked (global).
  Rect? _area;

  /// The capture, once the area is marked; then its outcome.
  Future<CaptureResult>? _capturing;
  CaptureResult? _result;
  bool _done = false;

  /// Takes the keys (Escape) from the editor, which gets them back after.
  final FocusNode _focus = FocusNode(debugLabel: 'capture area');
  FocusNode? _before;

  @override
  void initState() {
    super.initState();
    _before = FocusManager.instance.primaryFocus;
    _focus.requestFocus();
    _area = widget.initial;
    if (widget.result case final result?) _await(result);
  }

  @override
  void dispose() {
    final before = _before;
    if (_focus.hasFocus && before != null && before.context != null) before.requestFocus();
    _focus.dispose();
    super.dispose();
  }

  void _await(Future<CaptureResult> capturing) {
    _capturing = capturing;
    unawaited(
      capturing.then((r) {
        if (mounted) setState(() => _result = r);
      }),
    );
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  Rect? get _free => widget.free();

  void _down(PointerDownEvent event) {
    if (_pointer != null || _done || widget.isPalm(event)) return;
    final primary = event.kind != PointerDeviceKind.mouse || event.buttons == kPrimaryButton;
    // Captured: a press beside the bar ends it.
    if (_capturing != null || !primary) return _finish();
    final free = _free;
    if (free == null || !free.contains(event.position) || !widget.onSurface(event.position)) {
      return _finish();
    }
    _pointer = event.pointer;
    _from = event.position;
    setState(() => _area = null);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final free = _free;
    final to = free == null ? event.position : _clamp(event.position, free);
    setState(() => _area = Rect.fromPoints(_from!, to));
  }

  static Offset _clamp(Offset p, Rect r) =>
      Offset(p.dx.clamp(r.left, r.right), p.dy.clamp(r.top, r.bottom));

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final area = _area;
    if (area == null ||
        area.width < CaptureLayer.minDrag && area.height < CaptureLayer.minDrag ||
        area.width < 1 ||
        area.height < 1) {
      setState(() => _area = null);
      return;
    }
    // Within the gesture: the web's clipboard wants one.
    final capturing = widget.capture(area);
    if (capturing == null) {
      setState(() => _area = null);
      return;
    }
    setState(() => _await(capturing));
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    setState(() => _area = null);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      _finish();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final free = _free ?? (Offset.zero & screen);
    final scheme = Theme.of(context).colorScheme;
    final area = _area;
    return Material(
      type: MaterialType.transparency,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _key,
        child: Stack(
          children: [
            Positioned.fill(
              child: MouseRegion(
                cursor: _capturing == null ? SystemMouseCursors.precise : MouseCursor.defer,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _up,
                  onPointerCancel: _cancel,
                  child: CustomPaint(
                    key: const ValueKey('capture-area'),
                    painter: _AreaPainter(
                      area: area,
                      scrim: Surfaces.scrim(scheme.brightness),
                      edge: scheme.primary,
                    ),
                  ),
                ),
              ),
            ),
            if (_capturing == null)
              Positioned(
                left: free.left + Gaps.md,
                right: screen.width - free.right + Gaps.md,
                top: free.top + Gaps.md,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _Hint(onCancel: _finish),
                ),
              )
            else if (area != null)
              CustomSingleChildLayout(
                delegate: _BarLayout(area, free),
                child: CaptureResultBar(
                  result: _result,
                  onSave: _result?.shot == null ? null : () => widget.onSave(_result!.shot!),
                  onInsert: _result?.shot == null ? null : () => widget.onInsert(_result!.shot!),
                  onDone: _finish,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dims all but the [area] marked, edged in the accent.
class _AreaPainter extends CustomPainter {
  _AreaPainter({required this.area, required this.scrim, required this.edge});

  final Rect? area;
  final Color scrim;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Offset.zero & size;
    final area = this.area;
    final path = Path()..addRect(all);
    if (area != null) {
      path
        ..addRect(area)
        ..fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(path, Paint()..color = scrim);
    if (area == null) return;
    canvas.drawRect(
      area,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = Hairline.rule,
    );
  }

  @override
  bool shouldRepaint(_AreaPainter old) =>
      old.area != area || old.scrim != scrim || old.edge != edge;
}

/// Places the result bar centred below the area, else above it, else
/// inside its bottom; always within [free].
class _BarLayout extends SingleChildLayoutDelegate {
  _BarLayout(this.area, this.free);

  final Rect area;
  final Rect free;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    final room = free.deflate(Gaps.sm);
    final maxX = room.right - child.width;
    final x = (area.center.dx - child.width / 2).clamp(
      room.left,
      maxX < room.left ? room.left : maxX,
    );
    var y = area.bottom + Gaps.sm;
    if (y + child.height > room.bottom) y = area.top - Gaps.sm - child.height;
    if (y < room.top) y = (area.bottom - Gaps.sm - child.height).clamp(room.top, room.bottom);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_BarLayout old) => old.area != area || old.free != free;
}

class _Hint extends StatelessWidget {
  const _Hint({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: FloatingPanel(
        padding: const EdgeInsets.only(left: Gaps.md, right: Gaps.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.screenshot_region_rounded,
              size: Glyphs.menu,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: Gaps.sm),
            Flexible(child: Text(CaptureLayer.hint, style: theme.textTheme.bodyMedium)),
            const SizedBox(width: Gaps.sm),
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}
