import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/paper.dart';
import '../../../domain/stroke.dart';
import '../../../ink/pen/pen_config.dart';
import '../../../ink/render/stroke_renderer.dart';
import '../../../ui/app_theme.dart';
import 'ink_paper.dart';
import 'preview_strokes.dart';

/// What a [StrokePreview] draws.
enum PreviewSample {
  /// A few words of handwriting (the pen), or a highlight over lines of
  /// text (the highlighter).
  writing,

  /// One short stroke (a size on its own); the highlighter's is the same
  /// highlight as [writing].
  line,
}

/// Previews an ink with the real renderer, at its real size and colour, on
/// the paper the user writes on ([InkPaper]): handwriting on a faint rule
/// for the pen, a highlight across grey lines of text for the highlighter.
class StrokePreview extends StatelessWidget {
  const StrokePreview({
    super.key,
    required this.tool,
    required this.config,
    this.color,
    this.width,
    this.height = PreviewCard.defaultHeight,
    this.sample = PreviewSample.writing,
  });

  final InkTool tool;
  final PenConfig config;

  /// Overrides the config's selected colour / width.
  final int? color;
  final double? width;
  final double height;
  final PreviewSample sample;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _PreviewPainter(
          tool: tool,
          config: config,
          color: color ?? config.color,
          width: width ?? config.width,
          paper: InkPaper.of(context),
          sample: sample,
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter({
    required this.tool,
    required this.config,
    required this.color,
    required this.width,
    required this.paper,
    required this.sample,
  });

  final InkTool tool;
  final PenConfig config;
  final int color;
  final double width;
  final PaperColor paper;
  final PreviewSample sample;

  /// Space between the ink and the card's sides.
  static const double _side = Gaps.lg;

  @override
  void paint(Canvas canvas, Size size) {
    if (tool.isHighlighter) {
      _highlight(canvas, size);
    } else if (sample == PreviewSample.line) {
      _line(canvas, size);
    } else {
      _writing(canvas, size);
    }
  }

  void _ink(Canvas canvas, List<StrokePoint> points, double width) {
    final style = config.styleFor(tool);
    final path = StrokeRenderer.buildPath(points, width: width, style: style, complete: true);
    canvas.drawPath(path, StrokeRenderer.paintFor(color, style));
  }

  /// Handwriting on a faint rule; thicker pens write a little larger, as a
  /// hand does, while the words fit the card.
  void _writing(Canvas canvas, Size size) {
    final shown = math.min(width, size.height * 0.16);
    final box = Rect.fromLTRB(
      _side,
      shown / 2 + Gaps.sm,
      size.width - _side,
      size.height - shown / 2 - Gaps.md,
    );
    final x = math.min(PreviewStrokes.xHeightFor(box), 11 + shown * 1.6);
    final lineWidth = PreviewStrokes.widthInXHeights * x;
    final left = box.left + (box.width - lineWidth) / 2;
    final baseline = box.center.dy + PreviewStrokes.tallest * x / 2;
    canvas.drawLine(
      Offset(0, baseline + 0.5),
      Offset(size.width, baseline + 0.5),
      Paint()
        ..color = paper.pattern
        ..strokeWidth = 1,
    );
    for (final word in PreviewStrokes.handwriting(left, baseline, x)) {
      _ink(canvas, word, shown);
    }
  }

  /// One gentle stroke across the middle.
  void _line(Canvas canvas, Size size) {
    final shown = math.min(width, size.height * 0.4);
    final inset = _side + shown / 2;
    final mid = size.height / 2;
    final points = PreviewStrokes.highlight(
      Offset(inset, mid + 2),
      Offset(size.width - inset, mid - 2),
    );
    _ink(canvas, [for (final p in points) StrokePoint(p.x, p.y, 0.6)], shown);
  }

  /// Three lines of grey "text", the middle one highlighted from its start
  /// to about two thirds across.
  void _highlight(Canvas canvas, Size size) {
    final shown = math.min(width, size.height * 0.6);
    final mid = size.height / 2;
    const pitch = 17.0;
    final text = Paint()
      ..color = paper.text.withValues(alpha: 0.42)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5;
    for (final (row, words) in _rows.indexed) {
      final y = mid + (row - 1) * pitch;
      var x = _side;
      for (final w in words) {
        final end = math.min(x + w, size.width - _side);
        if (end - x > 4) canvas.drawLine(Offset(x, y), Offset(end, y), text);
        x += w + 7;
      }
    }
    final from = Offset(_side - 2 + shown * 0.15, mid + 1);
    final to = Offset(_side + (size.width - 2 * _side) * 0.68, mid);
    final points = PreviewStrokes.highlight(from, to);
    _ink(canvas, config.straight ? [points.first, points.last] : points, shown);
  }

  /// Word lengths of the three lines of "text" (the last one ends early).
  static const List<List<double>> _rows = [
    [30, 18, 44, 24, 36, 20, 40, 28, 34],
    [22, 40, 26, 34, 18, 46, 30, 24, 38],
    [36, 24, 30, 42, 20],
  ];

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.tool != tool ||
      old.config != config ||
      old.color != color ||
      old.width != width ||
      old.paper != paper ||
      old.sample != sample;
}

/// A [StrokePreview] on a card of the paper the user writes on, framed by a
/// hairline that sits quietly on light and dark chrome alike.
class PreviewCard extends StatelessWidget {
  const PreviewCard({
    super.key,
    required this.tool,
    required this.config,
    this.color,
    this.width,
    this.height = PreviewCard.defaultHeight,
    this.sample = PreviewSample.writing,
  });

  final InkTool tool;
  final PenConfig config;
  final int? color;
  final double? width;
  final double height;
  final PreviewSample sample;

  /// The height of the option panels' previews (ink and laser alike).
  static const double defaultHeight = 64;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: InkPaper.of(context).paper,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: StrokePreview(
        tool: tool,
        config: config,
        color: color,
        width: width,
        height: height,
        sample: sample,
      ),
    );
  }
}
