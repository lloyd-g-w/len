import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/pen/pen_config.dart';
import '../../../ink/render/stroke_renderer.dart';
import '../../../ui/app_theme.dart';

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

  /// Overrides the config's selected colour / width.
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
          color: color ?? config.color,
          width: width ?? config.width,
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
    final style = config.styleFor(tool);
    final path = StrokeRenderer.buildPath(
      points,
      tool: tool,
      width: shown,
      style: style,
      complete: true,
    );
    canvas.drawPath(path, StrokeRenderer.paintFor(color, style));
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.tool != tool || old.config != config || old.color != color || old.width != width;
}

/// A [StrokePreview] on a paper-white card, as the ink will look on a page.
class PreviewCard extends StatelessWidget {
  const PreviewCard({
    super.key,
    required this.tool,
    required this.config,
    this.width,
    this.height = 56,
  });

  final InkTool tool;
  final PenConfig config;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.xs),
      decoration: BoxDecoration(
        color: Palette.paper,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: StrokePreview(tool: tool, config: config, width: width, height: height),
    );
  }
}
