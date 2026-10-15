import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import 'zoom_window.dart';

/// The zoom window's frame on the page view: a hairline in the accent
/// over a faint wash (it marks where you are), the advance zone washed a
/// little deeper, a tab on its top edge and a square at its corner. Drag
/// the tab to move the frame (lines then start there), the square to size
/// it (a smaller frame magnifies more). Only these take pointers: the pen
/// writes inside the frame on the page as anywhere else.
class ZoomFrameOverlay extends StatefulWidget {
  const ZoomFrameOverlay({super.key, required this.zoom});

  final ZoomWindow zoom;

  /// The size handle's visible square, and the move tab's size (each
  /// grabbed over a full touch target, mostly outside the frame).
  static const double handle = 10;
  static const Size tab = Size(Gaps.xl, Gaps.sm);

  /// How far a handle's target reaches into the frame.
  static const double into = Gaps.sm;

  @override
  State<ZoomFrameOverlay> createState() => _ZoomFrameOverlayState();
}

/// The frame on screen: its rectangle, where its advance zone starts and
/// its move tab.
typedef _Geometry = ({Rect frame, double? zoneX, Rect tab});

class _ZoomFrameOverlayState extends State<ZoomFrameOverlay> {
  ZoomWindow get _zoom => widget.zoom;

  /// The frame's width (surface units) while its handle is dragged.
  double? _width;

  /// What moves the frame on screen (a scroll, a zoom, the window).
  late Listenable _moves = _movesOf(_zoom);

  static Listenable _movesOf(ZoomWindow zoom) => Listenable.merge([zoom, zoom.host.changes]);

  /// Whether the frame is on screen: the overlay rebuilds when that
  /// changes, not on every scroll frame (it is painted and placed from
  /// [_geometry] as the view moves).
  late final ValueNotifier<bool> _shown = ValueNotifier(_geometry() != null);

  @override
  void initState() {
    super.initState();
    _moves.addListener(_moved);
  }

  @override
  void didUpdateWidget(ZoomFrameOverlay old) {
    super.didUpdateWidget(old);
    if (old.zoom == widget.zoom) return;
    _moves.removeListener(_moved);
    _moves = _movesOf(_zoom)..addListener(_moved);
    _moved();
  }

  @override
  void dispose() {
    _moves.removeListener(_moved);
    _shown.dispose();
    super.dispose();
  }

  void _moved() => _shown.value = _geometry() != null;

  /// The frame on screen now; null without one or off screen.
  _Geometry? _geometry() {
    final frame = _zoom.frame;
    final rect = _zoom.frameRect;
    if (frame == null || rect == null) return null;
    final screen = _zoom.host.onScreen(frame.surfaceId, rect);
    if (screen == null) return null;
    final zone = screen.left + (_zoom.zoneStart! - rect.left) * screen.width / rect.width;
    return (frame: screen, zoneX: zone, tab: _tabRect(screen));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final hit = Targets.barHit(context);
    return ValueListenableBuilder(
      valueListenable: _shown,
      builder: (context, shown, _) => !shown
          ? const SizedBox.shrink()
          : Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _FramePainter(geometry: _geometry, color: accent, repaint: _moves),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomMultiChildLayout(
                    delegate: _HandlesLayout(_geometry, hit: hit, relayout: _moves),
                    children: [
                      LayoutId(
                        id: _Handle.move,
                        child: Semantics(
                          label: 'Zoom window frame',
                          hint: 'Drag to move where the zoom window writes',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (d) => _zoom.dragBy(d.delta),
                            onPanEnd: (_) => _zoom.dragEnd(),
                            onPanCancel: _zoom.dragEnd,
                            child: const MouseRegion(cursor: SystemMouseCursors.move),
                          ),
                        ),
                      ),
                      LayoutId(
                        id: _Handle.size,
                        child: Semantics(
                          label: 'Zoom window size',
                          hint: 'Drag to make the frame larger or smaller',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (_) => _width = _zoom.frameRect?.width,
                            onPanUpdate: (d) => _resize(d.delta, _geometry()?.frame.size),
                            onPanEnd: (_) => _width = null,
                            child: const MouseRegion(
                              cursor: SystemMouseCursors.resizeUpLeftDownRight,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// The move tab on [frame]'s top edge, at its left (the start of the
  /// line), kept within a narrow frame.
  static Rect _tabRect(Rect frame) {
    const tab = ZoomFrameOverlay.tab;
    final width = math.min(tab.width, frame.width);
    final left = frame.left + math.min(Gaps.md, math.max(0.0, frame.width - width));
    return Rect.fromLTWH(left, frame.top - tab.height, width, tab.height);
  }

  /// Grows the frame by [delta] along its diagonal (its shape is the box's).
  void _resize(Offset delta, Size? screen) {
    final width = _width;
    if (width == null || screen == null || screen.isEmpty) return;
    final diagonal = screen.width * screen.width + screen.height * screen.height;
    final grow = (delta.dx * screen.width + delta.dy * screen.height) / diagonal;
    _width = width * (1 + grow);
    _zoom.resizeTo(_width!);
  }
}

enum _Handle { move, size }

/// Places the handles' targets on the frame: the move tab's above the tab
/// (on the top edge at the left), the size square's at the bottom-right
/// corner; again whenever [relayout] notifies (the view moved).
class _HandlesLayout extends MultiChildLayoutDelegate {
  _HandlesLayout(this.geometry, {required this.hit, super.relayout});

  final _Geometry? Function() geometry;

  /// The side of a target.
  final double hit;

  @override
  void performLayout(Size size) {
    const into = ZoomFrameOverlay.into;
    // Off screen in the moment between the frame leaving and the rebuild.
    final at = geometry();
    final screen = at?.frame ?? Rect.fromLTWH(-4 * hit, -4 * hit, 0, 0);
    final tab = at?.tab ?? screen;
    final targets = {
      _Handle.move: Offset(tab.center.dx - hit / 2, screen.top + into - hit),
      _Handle.size: Offset(screen.right - into, screen.bottom - into),
    };
    for (final MapEntry(key: id, value: topLeft) in targets.entries) {
      layoutChild(id, BoxConstraints.tight(Size.square(hit)));
      positionChild(id, topLeft);
    }
  }

  @override
  bool shouldRelayout(_HandlesLayout old) => old.hit != hit;
}

class _FramePainter extends CustomPainter {
  _FramePainter({required this.geometry, required this.color, super.repaint});

  final _Geometry? Function() geometry;
  final Color color;

  /// The washes over the frame and over its advance zone.
  static const double wash = 0.05, zoneWash = 0.1;

  @override
  void paint(Canvas canvas, Size size) {
    final at = geometry();
    if (at == null) return;
    final (:frame, :zoneX, :tab) = at;
    canvas.drawRect(frame, Paint()..color = color.withValues(alpha: wash));
    final x = zoneX;
    if (x != null && x > frame.left && x < frame.right) {
      canvas.drawRect(
        Rect.fromLTRB(x, frame.top, frame.right, frame.bottom),
        Paint()..color = color.withValues(alpha: zoneWash),
      );
    }
    final rule = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = Hairline.width;
    canvas
      ..drawRect(frame.deflate(Hairline.width / 2), rule)
      ..drawRRect(
        RRect.fromRectAndCorners(
          tab,
          topLeft: const Radius.circular(Radii.xs),
          topRight: const Radius.circular(Radii.xs),
        ),
        Paint()..color = color,
      );
    const h = ZoomFrameOverlay.handle;
    canvas.drawRect(
      Rect.fromCenter(center: frame.bottomRight, width: h, height: h),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.color != color;
}
