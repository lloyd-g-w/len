import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ink/render/catmull_rom.dart';
import '../../../ink/render/laser_painter.dart';
import '../../../ink/render/laser_ribbon.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_picker/color_choices.dart';
import '../pen/option_controls.dart';

/// The laser pointer's settings: dot or trail, colour, size and how long
/// the trail lasts, with a live preview.
class LaserOptionsPanel extends StatelessWidget {
  const LaserOptionsPanel({super.key, required this.tools});

  final ToolSettings tools;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final laser = tools.laser;
        void update(LaserConfig config) => tools.laser = config;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OptionHeader(
              'Laser pointer',
              trailing: ResetButton<LaserConfig>(
                value: laser,
                defaults: const LaserConfig(),
                onChanged: update,
              ),
            ),
            const SizedBox(height: Gaps.sm),
            LaserPreview(config: laser),
            const SizedBox(height: Gaps.sm),
            SegmentedButton<LaserMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: LaserMode.dot,
                  icon: Icon(Symbols.circle_rounded, fill: 1, size: 12),
                  label: Text('Dot'),
                ),
                ButtonSegment(
                  value: LaserMode.trail,
                  icon: Icon(Symbols.gesture_rounded),
                  label: Text('Trail'),
                ),
              ],
              selected: {laser.mode},
              onSelectionChanged: (s) => update(laser.copyWith(mode: s.single)),
            ),
            const SizedBox(height: Gaps.md),
            ColorChoices(
              color: laser.color,
              palette: LaserConfig.presets,
              recent: tools.recentColors,
              onChanged: (c) => update(laser.copyWith(color: c)),
            ),
            const SizedBox(height: Gaps.sm),
            OptionSlider(
              label: 'Size',
              value: laser.size,
              min: LaserConfig.minSize,
              max: LaserConfig.maxSize,
              // On screen, whatever the zoom: no unit to read.
              showValue: false,
              display: (v) =>
                  percent((v - LaserConfig.minSize) / (LaserConfig.maxSize - LaserConfig.minSize)),
              onChanged: (v) => update(laser.copyWith(size: v.roundToDouble())),
            ),
            if (laser.mode == LaserMode.trail)
              OptionSlider(
                label: 'Trail lasts',
                value: laser.duration.inMilliseconds / 1000,
                min: LaserConfig.minDuration.inMilliseconds / 1000,
                max: LaserConfig.maxDuration.inMilliseconds / 1000,
                display: (v) => '${v.toStringAsFixed(1)} s',
                onChanged: (v) => update(
                  laser.copyWith(duration: Duration(milliseconds: (v * 10).round() * 100)),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A sample of the laser as configured: a fading curve ending in the dot
/// (trail), or just the dot, on a dark backdrop like a presentation.
class LaserPreview extends StatelessWidget {
  const LaserPreview({super.key, required this.config});

  final LaserConfig config;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.sm),
      child: SizedBox(height: 64, child: CustomPaint(painter: _PreviewPainter(config))),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.config);

  final LaserConfig config;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF26282C));
    final color = Color(config.color);
    final end = Offset(size.width * 0.82, size.height * 0.5);
    if (config.mode == LaserMode.trail) {
      final xs = <double>[], ys = <double>[], alphas = <double>[];
      const n = 24;
      for (var i = 0; i <= n; i++) {
        final t = i / n;
        xs.add(size.width * (0.1 + 0.72 * t));
        ys.add(size.height * (0.5 + 0.28 * math.sin(t * 2 * math.pi)));
        alphas.add(t);
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
