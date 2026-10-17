import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ink/render/laser_painter.dart';
import '../../../ink/render/laser_ribbon.dart';
import '../../../ink/render/laser_stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../pen/stroke_preview.dart';

/// A sample of the laser as configured: a fading stroke shaped as the trail
/// is (its ends, pressure sensitivity and stabiliser showing), or the dot,
/// on a dark backdrop like a presentation.
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
    if (config.mode == LaserMode.dot) {
      LaserPainter.paintDot(canvas, size.center(Offset.zero), config.size * 0.8, color, 1);
      return;
    }
    // A finished stroke through the pen's engine, so its ends, pressure
    // (pressing harder towards the middle) and stabiliser show; no dot over
    // its end. A held trail shows all of it; else it fades with age.
    final stroke = LaserStroke(LaserStroke.specFor(config, 1), 1);
    const n = 24;
    final alphas = <double>[];
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      stroke.add(
        i,
        size.width * (0.1 + 0.8 * t),
        size.height * (0.5 + 0.28 * math.sin(t * 2 * math.pi)),
        0.2 + 0.7 * math.sin(t * math.pi),
      );
      alphas.add(config.fade == LaserFade.pause ? 1 : 0.25 + 0.75 * t);
    }
    final glow = LaserRibbon.glow()..color = color;
    final core = LaserRibbon.core()..color = color;
    stroke
      ..end()
      ..emit(glow, core, alphaOf: (i) => alphas[i], glowScale: LaserPainter.glowScale);
    glow.draw(canvas);
    core.draw(canvas);
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.config != config;
}
