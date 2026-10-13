import 'dart:ui';

import '../viewport.dart';
import 'selection_frame.dart';

/// Screen-space layout of the selection frame's handles, shared by the
/// painter and the lasso tool's hit testing.
abstract final class SelectionChrome {
  /// Distance of the rotate handle above the frame's top edge (pixels).
  static const double rotateOffset = 30;

  /// Pointer slop around a handle (pixels).
  static const double hitRadius = 18;

  /// Edge handles are left out when the frame is smaller than this on
  /// screen, so they neither crowd the corners nor cover its inside.
  static const double minEdgeHandleSpan = 56;

  /// Handles stay this far inside the view, so a frame reaching past the
  /// screen's edge (a full-width shape on a phone) can still be resized.
  static const double edgeInset = 12;

  /// Screen positions of the handles shown for [frame] (kept [edgeInset]
  /// inside the view).
  static Map<SelectionHandle, Offset> handles(SelectionFrame frame, ViewportController viewport) {
    final size = viewport.size;
    final inside = size.width > 4 * edgeInset && size.height > 4 * edgeInset
        ? (Offset.zero & size).deflate(edgeInset)
        : null;
    Offset at(Offset fraction) {
      final p = viewport.toScreen(frame.at(fraction));
      if (inside == null) return p;
      return Offset(p.dx.clamp(inside.left, inside.right), p.dy.clamp(inside.top, inside.bottom));
    }

    final width = frame.rect.width * viewport.scale;
    final height = frame.rect.height * viewport.scale;
    final result = <SelectionHandle, Offset>{};
    for (final h in SelectionHandle.values) {
      if (h == SelectionHandle.rotate) continue;
      final small = width < minEdgeHandleSpan || height < minEdgeHandleSpan;
      if (!h.isCorner && small) continue;
      result[h] = at(h.fraction);
    }
    final rotate = viewport.toScreen(frame.at(const Offset(0.5, 0))) + frame.up * rotateOffset;
    result[SelectionHandle.rotate] = inside == null
        ? rotate
        : Offset(
            rotate.dx.clamp(inside.left, inside.right),
            rotate.dy.clamp(inside.top, inside.bottom),
          );
    return result;
  }

  /// The handle under [screen], if any (the rotate handle and corners win
  /// over edges when they overlap). Inside the frame the reach is shorter,
  /// so small selections can still be dragged by their middle.
  static SelectionHandle? hit(SelectionFrame frame, ViewportController viewport, Offset screen) {
    SelectionHandle? best;
    final inside = frame.contains(viewport.toWorld(screen));
    var bestDistance = inside ? hitRadius / 2 : hitRadius;
    for (final entry in handles(frame, viewport).entries) {
      final d = (entry.value - screen).distance;
      final preferred = entry.key == SelectionHandle.rotate || entry.key.isCorner;
      if (d < bestDistance || (preferred && !inside && d <= hitRadius && d < bestDistance + 4)) {
        best = entry.key;
        bestDistance = d;
      }
    }
    return best;
  }
}
