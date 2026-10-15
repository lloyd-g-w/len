import 'package:flutter/material.dart';

import '../../../domain/paper.dart';
import '../../../ink/render/paper_painter.dart';
import '../../../ui/app_theme.dart';

/// The top-left corner of a page (or a canvas) at actual size (100 %
/// zoom): how far apart the lines are, how heavy, in which colours, with
/// the margin line and header. Updates live as the options change.
class PaperSwatch extends StatelessWidget {
  const PaperSwatch({super.key, required this.template, this.canvas = false, this.height = 120});

  final PageTemplate template;

  /// Shows a canvas background (no page: no header or margin).
  final bool canvas;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Paper preview at actual size',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sm),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _SwatchPainter(template: template, canvas: canvas),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter({required this.template, required this.canvas});

  final PageTemplate template;
  final bool canvas;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    canvas.drawRect(area, Paint()..color = template.color.paper);
    final page = this.canvas ? null : Offset.zero & template.size;
    canvas.save();
    canvas.clipRect(area);
    PaperRenderer.paintPattern(
      canvas,
      template.paper,
      template.color,
      area,
      page: page,
      // A logical pixel per unit, as the canvas at 100 % (on any screen).
      scale: 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.template != template || old.canvas != canvas;
}
