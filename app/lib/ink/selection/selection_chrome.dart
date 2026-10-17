import 'dart:ui';

import '../../domain/shape_geometry.dart';
import '../shapes/polyline.dart';
import '../shapes/shape_builder.dart';
import '../shapes/shape_handles.dart';
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
  /// inside the view). Around a single [shape] its own points are the
  /// handles ([shapeHandles]): the frame only keeps its rotate handle, and
  /// lines and arrows not even that (their ends turn them).
  static Map<SelectionHandle, Offset> handles(
    SelectionFrame frame,
    ViewportController viewport, {
    ShapeGeometry? shape,
  }) {
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
    if (shape != null && !shape.isClosed) return result;
    for (final h in SelectionHandle.values) {
      if (h == SelectionHandle.rotate || shape != null) continue;
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
  static SelectionHandle? hit(
    SelectionFrame frame,
    ViewportController viewport,
    Offset screen, {
    ShapeGeometry? shape,
  }) {
    SelectionHandle? best;
    final inside = frame.contains(viewport.toWorld(screen));
    var bestDistance = inside ? hitRadius / 2 : hitRadius;
    for (final entry in handles(frame, viewport, shape: shape).entries) {
      final d = (entry.value - screen).distance;
      final preferred = entry.key == SelectionHandle.rotate || entry.key.isCorner;
      if (d < bestDistance || (preferred && !inside && d <= hitRadius && d < bestDistance + 4)) {
        best = entry.key;
        bestDistance = d;
      }
    }
    return best;
  }

  /// [shape]'s handles as shown ([ShapeHandles.of]): their index, role
  /// and screen position. Secondary handles (sides, centres, bends,
  /// tangents) step aside where they would crowd a primary one (within
  /// [crowd] pixels: a small shape shows its corners or radii only). A
  /// tangent shorter than [crowd] on screen (none at all: a corner anchor)
  /// is shown [crowd] from its anchor, along itself or else along its
  /// segment ([ShapeHandles.tangentTowards]), so it can still be pulled
  /// out; it steps aside where that spot crowds another primary handle.
  static List<({int index, ShapeHandle handle, Offset at})> shapeHandles(
    ShapeGeometry shape,
    ViewportController viewport,
  ) {
    final all = ShapeHandles.of(shape);
    final screen = [for (final h in all) viewport.toScreen(h.at)];
    final primary = [
      for (final (i, h) in all.indexed)
        if (h.role.isPrimary) screen[i],
    ];
    bool crowds(Offset at, [Offset? own]) =>
        primary.any((p) => p != own && (p - at).distance < crowd);
    Offset? place(int i) {
      final h = all[i];
      if (h.role.isPrimary) return screen[i];
      final anchor = h.anchor;
      if (anchor == null) return crowds(screen[i]) ? null : screen[i];
      final from = viewport.toScreen(anchor), arm = screen[i] - from;
      if (arm.distance >= crowd) return screen[i];
      final towards = arm.distance >= 1
          ? arm
          : viewport.toScreen(ShapeHandles.tangentTowards(shape, i)) - from;
      if (towards.distance < 1) return null;
      final at = from + towards / towards.distance * crowd;
      return crowds(at, from) ? null : at;
    }

    return [
      for (final (i, h) in all.indexed)
        if (place(i) case final at?) (index: i, handle: h, at: at),
    ];
  }

  /// How close (pixels) a secondary handle may come to a primary one.
  static const double crowd = 24;

  /// Reach of a shape's handles (pixels) by input: a fingertip
  /// (`Targets.touch` across), a pen, a mouse.
  static double shapeHitRadius([PointerDeviceKind kind = PointerDeviceKind.touch]) =>
      switch (kind) {
        PointerDeviceKind.touch || PointerDeviceKind.unknown => 24,
        PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => 22,
        PointerDeviceKind.mouse || PointerDeviceKind.trackpad => 18,
      };

  /// The index of [shape]'s handle nearest to [screen], if any is within
  /// reach: [shapeHitRadius] for [kind] outside the [frame], less inside
  /// it (so a small shape can still be moved by its middle), and not when
  /// the frame's rotate handle is nearer.
  static int? shapeHandleAt(
    ShapeGeometry shape,
    ViewportController viewport,
    Offset screen, {
    SelectionFrame? frame,
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) {
    final full = shapeHitRadius(kind);
    var reach = full;
    if (frame != null && frame.contains(viewport.toWorld(screen))) {
      final side = frame.rect.shortestSide * viewport.scale;
      reach = (side / 4).clamp(hitRadius / 2, full);
    }
    int? best;
    var bestDistance = reach;
    for (final h in shapeHandles(shape, viewport)) {
      final d = (h.at - screen).distance;
      if (d <= bestDistance) {
        best = h.index;
        bestDistance = d;
      }
    }
    final rotate = frame == null
        ? null
        : handles(frame, viewport, shape: shape)[SelectionHandle.rotate];
    if (rotate != null && (rotate - screen).distance < bestDistance) return null;
    return best;
  }

  /// Whether a press at [screen] grabs the selection in [frame] to move
  /// it: anywhere inside the frame, but only near the stroke itself for a
  /// single line or arrow (its frame, not shown, may span much of the view).
  static bool grabs(
    SelectionFrame frame,
    ViewportController viewport,
    Offset screen, {
    ShapeGeometry? shape,
  }) {
    if (shape == null || shape.isClosed) return frame.contains(viewport.toWorld(screen));
    final outline = [for (final p in ShapeBuilder.outline(shape)) viewport.toScreen(p)];
    for (var i = 1; i < outline.length; i++) {
      if (Polyline.distanceToSegment(screen, outline[i - 1], outline[i]) <= hitRadius) return true;
    }
    return false;
  }
}
