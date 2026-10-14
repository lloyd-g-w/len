import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import 'zoom_window.dart';

/// The zoom window's frame on the page view: a 2-dp rule in the accent
/// (it marks where you are), the start of the advance zone, and a handle
/// at its corner. Drag the frame to move it (lines then start there),
/// drag the handle to size it (a smaller frame magnifies more).
class ZoomFrameOverlay extends StatefulWidget {
  const ZoomFrameOverlay({super.key, required this.zoom});

  final ZoomWindow zoom;

  /// The handle's visible square (it is grabbed over a full touch target).
  static const double handle = 10;

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
      // Tiny frames (zoomed far out) can still be grabbed.
      final grab = Rect.fromCenter(
        center: screen.center,
        width: math.max(screen.width, hit),
        height: math.max(screen.height, hit),
      );
      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FramePainter(frame: screen, zoneX: zone, color: accent),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: grab,
            child: Semantics(
              label: 'Zoom window frame',
              hint: 'Drag to move where the zoom window writes',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => _zoom.dragBy(d.delta),
                onPanEnd: (_) => _zoom.dragEnd(),
                onPanCancel: _zoom.dragEnd,
              ),
            ),
          ),
          Positioned.fromRect(
            rect: Rect.fromCenter(center: screen.bottomRight, width: hit, height: hit),
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
  _FramePainter({required this.frame, required this.zoneX, required this.color});

  final Rect frame;
  final double? zoneX;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rule = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = Hairline.rule;
    canvas.drawRect(frame.deflate(Hairline.rule / 2), rule);
    final x = zoneX;
    if (x != null && x > frame.left && x < frame.right) {
      canvas.drawLine(
        Offset(x, frame.top),
        Offset(x, frame.bottom),
        Paint()
          ..color = color
          ..strokeWidth = Hairline.width,
      );
    }
    const h = ZoomFrameOverlay.handle;
    canvas.drawRect(
      Rect.fromCenter(center: frame.bottomRight, width: h, height: h),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.frame != frame || old.zoneX != zoneX || old.color != color;
}
