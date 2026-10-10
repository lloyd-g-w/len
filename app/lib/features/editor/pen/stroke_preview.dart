import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/pen/pen_config.dart';
import '../../../ink/render/stroke_renderer.dart';

/// Draws a sample S-curve with real ink, to preview a pen's look and feel.
class StrokePreview extends StatelessWidget {
  const StrokePreview({
    super.key,
    required this.tool,
    required this.config,
    this.color,
    this.width,
    this.height = 44,
  });

  final InkTool tool;
  final PenConfig config;

  /// Overrides the config's current colour / width.
  final int? color;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _PreviewPainter(
          tool: tool,
          config: config,
          color: color ?? config.current.color,
          width: width ?? config.current.width,
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
  });

  final InkTool tool;
  final PenConfig config;
  final int color;
  final double width;

  /// A gentle S-curve whose pressure swells in the middle.
  static List<StrokePoint> samplePoints(Size size, double inset) {
    const n = 64;
    final w = size.width - 2 * inset, h = size.height - 2 * inset;
    return [
      for (var i = 0; i <= n; i++)
        StrokePoint(
          inset + w * i / n,
          inset + h * (0.5 - 0.42 * math.sin(i / n * 2 * math.pi)),
          0.25 + 0.75 * math.sin(i / n * math.pi),
        ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Keep thick pens inside the preview.
    final shown = math.min(width, size.height * 0.4);
    final points = samplePoints(size, shown / 2 + 4);
    final style = config.styleFor(tool, shown);
    final path = StrokeRenderer.buildPath(
      points,
      tool: tool,
      width: shown,
      style: style,
      complete: true,
    );
    canvas.drawPath(path, StrokeRenderer.paintFor(tool, color, style));
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.tool != tool || old.config != config || old.color != color || old.width != width;
}
