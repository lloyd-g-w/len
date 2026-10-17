import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ink/render/catmull_rom.dart';
import '../../../ink/render/laser_painter.dart';
import '../../../ink/render/laser_ribbon.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../pen/stroke_preview.dart';

/// A sample of the laser as configured: a fading curve ending in the dot
/// (trail), or just the dot, on a dark backdrop like a presentation.
class LaserPreview extends StatelessWidget {
  const LaserPreview({super.key, required this.config, this.height = PreviewCard.defaultHeight});

  final LaserConfig config;
  final double height;

  /// The backdrop: a neutral dark grey in both themes, like a dimmed
  /// presentation (the laser's glow needs the dark).
  static final Color backdrop = Tones.dark.board;

  @override
  Widget build(BuildContext context) {
    // Framed like the ink previews: a Rule edge, radius sm.
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: backdrop,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: SizedBox(
        height: height,
        child: CustomPaint(painter: _PreviewPainter(config)),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.config);

  final LaserConfig config;

  @override
  void paint(Canvas canvas, Size size) {
    final color = Color(config.color);
    final end = Offset(size.width * 0.82, size.height * 0.5);
    if (config.mode == LaserMode.trail) {
      final xs = <double>[], ys = <double>[], alphas = <double>[];
      const n = 24;
      for (var i = 0; i <= n; i++) {
        final t = i / n;
        xs.add(size.width * (0.1 + 0.72 * t));
        ys.add(size.height * (0.5 + 0.28 * math.sin(t * 2 * math.pi)));
        // A held trail shows all of it; else it fades with age.
        alphas.add(config.fade == LaserFade.pause ? 1 : t);
      }
      final curve = CatmullRom.densify(xs, ys, alphas, 3);
      LaserRibbon.glow()
        ..color = color
        ..add(curve.x, curve.y, curve.r, config.size / 2 * LaserPainter.glowScale)
        ..draw(canvas);
      LaserRibbon.core()
        ..color = color
        ..add(curve.x, curve.y, curve.r, config.size / 2)
        ..draw(canvas);
    }
    final radius = config.mode == LaserMode.dot ? config.size * 0.8 : config.size / 2;
    LaserPainter.paintDot(
      canvas,
      config.mode == LaserMode.dot ? size.center(Offset.zero) : end,
      radius,
      color,
      1,
    );
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.config != config;
}
