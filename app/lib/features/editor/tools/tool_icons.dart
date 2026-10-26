import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ink/shapes/shape_builder.dart';
import '../../../ink/tool_settings.dart';

part 'tool_icon_painter.dart';

/// The editor's tool glyphs, in one place (DESIGN §4).
///
/// Commands (undo, menus, insert sources) are Material Symbols Rounded;
/// the tools you hold are drawn here, on the symbols' 24-unit grid with
/// their weight: a 1.7-unit stroke (about weight 300 at 20 dp), round ends
/// and joins, rounded corners, a 2-unit margin. The instruments (pen,
/// highlighter, eraser, laser) are held at 45°, writing end down-left, and
/// share the lasso's tail angle. The part that touches the page (a nib,
/// the eraser's band, the laser's dot, the lasso's knot) is solid. Selected
/// tools look the same: never filled, the plate behind them marks the
/// choice.
enum ToolIconKind {
  /// A fineliner: a rounded barrel, a cone, a solid nib.
  pen,

  /// A marker: a wider rounded barrel with a solid chisel tip.
  highlighter,

  /// A rounded block eraser with a solid band at its working end.
  eraser,

  /// A loop of rope in round dashes, a round knot and a curling tail.
  lasso,

  /// A dashed rounded marquee (the lasso's rectangle shape).
  lassoRectangle,

  /// A slim rounded pointer casting a dot of light in a soft halo.
  laser,

  /// A capital T with round ends.
  text,

  /// Insert ⊕.
  insert,

  /// A whole stroke (the eraser removes the stroke it touches).
  eraseStroke,

  /// A stroke with a gap (the eraser removes only what it covers).
  erasePartial,

  /// The laser's dot alone, in its halo.
  laserDot,

  /// The laser's trail: a stroke ending in its dot.
  laserTrail,
}

/// A tool glyph of [kind], sized and coloured by the [IconTheme]
/// (as an [Icon] is), so it sits among symbols unchanged.
class ToolIcon extends StatelessWidget {
  const ToolIcon(this.kind, {super.key, this.size});

  final ToolIconKind kind;

  /// The glyph's square; defaults to the [IconTheme]'s size.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final color = theme.color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox.square(
      dimension: size ?? theme.size ?? 24,
      child: CustomPaint(painter: _ToolIconPainter(kind, color)),
    );
  }
}

/// A shape drawn with the same outline the Shape tool produces, in the
/// ambient icon colour, on the tool glyphs' grid and stroke, its corners
/// rounded. An outline, as the tool draws, selected or not.
class ShapeGlyph extends StatelessWidget {
  const ShapeGlyph(this.kind, {super.key, this.size = 19});

  final ShapeKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final color = theme.color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _ShapeGlyphPainter(kind, color)),
    );
  }
}

class _ShapeGlyphPainter extends CustomPainter {
  _ShapeGlyphPainter(this.kind, this.color);

  final ShapeKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / _grid;
    // The outline's outer edge on the grid's margin, as the other glyphs'.
    final inset = (_margin + _stroke / 2 + 0.5) * unit;
    final open = !kind.isClosed;
    // Lines and arrows run corner to corner; closed shapes fill the box.
    final a = Offset(inset, open ? size.height - inset : inset);
    final b = Offset(size.width - inset, open ? inset : size.height - inset);
    final outline = ShapeBuilder.outline(ShapeBuilder.dragged(kind, a, b));
    // Polygons get soft corners; curves are dense enough to stay as they
    // are, and an arrow's head keeps its point (round joins soften it).
    final path = switch (kind) {
      ShapeKind.rectangle ||
      ShapeKind.triangle ||
      ShapeKind.diamond ||
      ShapeKind.polygon ||
      ShapeKind.star => _roundedPolygon(outline, closed: true, radius: 2.5 * unit),
      _ => Path()..addPolygon(outline, false),
    };
    canvas.drawPath(path, _line(color, unit));
  }

  @override
  bool shouldRepaint(_ShapeGlyphPainter old) => old.kind != kind || old.color != color;
}
