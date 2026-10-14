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

class _ZoomFrameOverlayState extends State<ZoomFrameOverlay> {
  ZoomWindow get _zoom => widget.zoom;

  /// The frame's width (surface units) while its handle is dragged.
  double? _width;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_zoom, _zoom.host.changes]),
    builder: (context, _) {
      final frame = _zoom.frame;
      final rect = _zoom.frameRect;
      if (frame == null || rect == null) return const SizedBox.shrink();
      final screen = _zoom.host.onScreen(frame.surfaceId, rect);
      if (screen == null) return const SizedBox.shrink();
      final zone = screen.left + (_zoom.zoneStart! - rect.left) * screen.width / rect.width;
      final accent = Theme.of(context).colorScheme.primary;
      final hit = Targets.barHit(context);
      const into = ZoomFrameOverlay.into;
      // The tab sits on the top edge at the left, the target above it.
      final tab = _tabRect(screen);
      final move = Rect.fromLTWH(tab.center.dx - hit / 2, screen.top + into - hit, hit, hit);
      final size = Rect.fromLTWH(screen.right - into, screen.bottom - into, hit, hit);
      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FramePainter(frame: screen, zoneX: zone, tab: tab, color: accent),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: move,
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
          Positioned.fromRect(
            rect: size,
            child: Semantics(
              label: 'Zoom window size',
              hint: 'Drag to make the frame larger or smaller',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => _width = rect.width,
                onPanUpdate: (d) => _resize(d.delta, screen.size),
                onPanEnd: (_) => _width = null,
                child: const MouseRegion(cursor: SystemMouseCursors.resizeUpLeftDownRight),
              ),
            ),
          ),
        ],
      );
    },
  );

  /// The move tab on [frame]'s top edge, at its left (the start of the
  /// line), kept within a narrow frame.
  static Rect _tabRect(Rect frame) {
    const tab = ZoomFrameOverlay.tab;
    final width = math.min(tab.width, frame.width);
    final left = frame.left + math.min(Gaps.md, math.max(0.0, frame.width - width));
    return Rect.fromLTWH(left, frame.top - tab.height, width, tab.height);
  }

  /// Grows the frame by [delta] along its diagonal (its shape is the box's).
  void _resize(Offset delta, Size screen) {
    final width = _width;
    if (width == null || screen.isEmpty) return;
    final diagonal = screen.width * screen.width + screen.height * screen.height;
    final grow = (delta.dx * screen.width + delta.dy * screen.height) / diagonal;
    _width = width * (1 + grow);
    _zoom.resizeTo(_width!);
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({required this.frame, required this.zoneX, required this.tab, required this.color});

  final Rect frame, tab;
  final double? zoneX;
  final Color color;

  /// The washes over the frame and over its advance zone.
  static const double wash = 0.05, zoneWash = 0.1;

  @override
  void paint(Canvas canvas, Size size) {
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
  bool shouldRepaint(_FramePainter old) =>
      old.frame != frame || old.zoneX != zoneX || old.tab != tab || old.color != color;
}
