import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../remote_ink.dart';
import '../viewport.dart';

/// Paints the strokes other devices are writing right now ([RemoteInk]) on
/// the surfaces of a view: over the committed ink, as the writer sees
/// their own live stroke (built as it grows, see [RemoteInk.outlinesOn]).
class RemoteInkPainter extends CustomPainter {
  RemoteInkPainter({required this.remote, required this.viewport, required this.frameOf})
    : super(repaint: Listenable.merge([remote, viewport]));

  final RemoteInk remote;
  final ViewportController viewport;

  /// Where surface [id] lies in [viewport]'s world (a page's frame; the
  /// canvas: [Rect.largest]), or null when this view does not show it.
  final Rect? Function(String id) frameOf;

  @override
  void paint(Canvas canvas, Size size) {
    if (remote.isEmpty) return;
    for (final surface in remote.surfaces) {
      final frame = frameOf(surface);
      if (frame == null) continue;
      final outlines = remote.outlinesOn(surface);
      if (outlines.isEmpty) continue;
      canvas
        ..save()
        ..translate(viewport.offset.dx, viewport.offset.dy)
        ..scale(viewport.scale);
      if (frame != Rect.largest) {
        canvas
          ..translate(frame.left, frame.top)
          ..clipRect(Offset.zero & frame.size);
      }
      for (final (path, paint) in outlines) {
        canvas.drawPath(path, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(RemoteInkPainter old) =>
      old.remote != remote || old.viewport != viewport || old.frameOf != frameOf;
}
