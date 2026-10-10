import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../../domain/chunk_grid.dart';
import '../../../ink/viewport.dart';

/// Maps a world rectangle into a minimap box, uniformly scaled and
/// centred.
class MinimapProjection {
  MinimapProjection(Rect world, this.size) {
    final fit = math.min(size.width / world.width, size.height / world.height);
    scale = fit.isFinite && fit > 0 ? fit : 1;
    origin = size.center(Offset.zero) - world.center * scale;
  }

  /// The area a minimap should show: all populated chunks and the current
  /// view, with a margin.
  static Rect extentOf(Iterable<ChunkKey> chunks, Rect visible) {
    var extent = visible;
    for (final key in chunks) {
      extent = extent.expandToInclude(ChunkGrid.rectOf(key));
    }
    return extent.inflate(math.max(extent.width, extent.height) * 0.06);
  }

  final Size size;
  late final double scale;
  late final Offset origin;

  Offset toMap(Offset world) => origin + world * scale;
  Rect rectToMap(Rect world) => Rect.fromPoints(toMap(world.topLeft), toMap(world.bottomRight));
  Offset toWorld(Offset map) => (map - origin) / scale;
}

/// Colours of the minimap.
class MinimapColors {
  const MinimapColors({required this.ink, required this.view, required this.origin});

  /// Populated chunks (more strokes → more opaque).
  final Color ink;

  /// The visible area outline.
  final Color view;

  /// The world origin marker.
  final Color origin;
}

/// Draws populated chunks (shaded by how many strokes they hold), the
/// origin and the visible area.
class MinimapPainter extends CustomPainter {
  MinimapPainter({required this.density, required this.viewport, required this.colors, this.frozen})
    : super(repaint: viewport);

  final Map<ChunkKey, int> density;
  final ViewportController viewport;
  final MinimapColors colors;

  /// A fixed projection (kept while dragging so the map holds still).
  final MinimapProjection? frozen;

  /// Strokes in a chunk at which its cell is fully opaque.
  static const int denseChunk = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = viewport.visibleWorld;
    final map =
        frozen ?? MinimapProjection(MinimapProjection.extentOf(density.keys, visible), size);
    canvas.clipRect(Offset.zero & size);
    final cell = Paint();
    for (final MapEntry(:key, :value) in density.entries) {
      final t = math.min(1.0, 0.3 + 0.7 * value / denseChunk);
      cell.color = colors.ink.withValues(alpha: colors.ink.a * t);
      // At least a pixel, so lone strokes stay visible on a huge canvas.
      final r = map.rectToMap(ChunkGrid.rectOf(key));
      canvas.drawRect(
        Rect.fromCenter(
          center: r.center,
          width: math.max(1.5, r.width),
          height: math.max(1.5, r.height),
        ),
        cell,
      );
    }
    final o = map.toMap(Offset.zero);
    final cross = Paint()
      ..color = colors.origin
      ..strokeWidth = 1;
    canvas
      ..drawLine(o - const Offset(4, 0), o + const Offset(4, 0), cross)
      ..drawLine(o - const Offset(0, 4), o + const Offset(0, 4), cross);
    final view = map.rectToMap(visible);
    canvas
      ..drawRect(view, Paint()..color = colors.view.withValues(alpha: 0.12))
      ..drawRect(
        view,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = colors.view,
      );
  }

  @override
  bool shouldRepaint(MinimapPainter old) =>
      old.density != density ||
      old.viewport != viewport ||
      old.colors != colors ||
      old.frozen != frozen;
}
