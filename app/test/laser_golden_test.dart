import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/tools/laser_options_panel.dart';
import 'package:len/ink/render/laser_painter.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/laser.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/ui/app_theme.dart';

import 'content_golden_test.dart' show loadFonts;

/// A trail drawn over 1.2 s (a loop then a wave), seen 1.2 s after it began;
/// pressed lightly at the ends and hard in the middle; with [lift], the
/// pointer lifted at the end (the end taper forms).
LaserTrail sampleTrail(LaserConfig config, Offset origin, {bool lift = false}) {
  final trail = LaserTrail()..config = config;
  const n = 140;
  for (var i = 0; i < n; i++) {
    final t = i / n;
    final p =
        origin +
        Offset(
          40 + 220 * t + 30 * math.cos(t * 4 * math.pi),
          70 + 40 * math.sin(t * 4 * math.pi) - 20 * t,
        );
    final pressure = 0.15 + 0.8 * math.sin(t * math.pi);
    i == 0 ? trail.down(p, pressure: pressure) : trail.move(p, pressure: pressure);
    trail.tick(t * 1200);
  }
  if (lift) {
    trail
      ..up()
      ..tick(1200);
  }
  return trail;
}

void main() {
  testWidgets('laser pointer: trail and dot, colours, options panel', (tester) async {
    await loadFonts();
    tester.view
      ..physicalSize = const Size(980, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final viewport = ViewportController();
    addTearDown(viewport.dispose);
    final configs = [
      const LaserConfig(),
      const LaserConfig(colorIndex: 1, sizes: [9], sizeIndex: 0),
      const LaserConfig(colorIndex: 2, sizeIndex: 0),
      const LaserConfig(mode: LaserMode.dot, sizeIndex: 2),
      // The pen's feel: round ends with full pressure sensitivity, and
      // tapered ends; held, so the start shows too.
      const LaserConfig(sizeIndex: 2, thinning: 1, fade: LaserFade.pause, ends: PenEnds()),
      const LaserConfig(
        colorIndex: 2,
        sizeIndex: 2,
        fade: LaserFade.pause,
        ends: PenEnds(style: StrokeEnds.tapered),
      ),
    ];
    LaserTrail sample(int i, LaserConfig c) =>
        sampleTrail(c, Offset(20.0 + (i % 2) * 330, 10.0 + (i ~/ 2) * 130), lift: i >= 4);
    final trails = [for (final (i, c) in configs.indexed) sample(i, c)];
    // Same strokes on dark paper (bottom half).
    final dark = [for (final (i, c) in configs.indexed) sample(i, c)];
    final tools = ToolSettings()
      ..laser = const LaserConfig(colorIndex: 1, sizes: [4, 9, 12], fade: LaserFade.pause);
    addTearDown(tools.dispose);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Row(
          children: [
            SizedBox(
              width: 680,
              child: Column(
                children: [
                  Expanded(
                    child: ColoredBox(
                      color: Colors.white,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          for (final t in trails)
                            CustomPaint(
                              painter: LaserPainter(trail: t, viewport: viewport),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: const Color(0xFF1E1F22),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          for (final t in dark)
                            CustomPaint(
                              painter: LaserPainter(trail: t, viewport: viewport),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Material(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LaserOptionsPanel(tools: tools),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/laser.png'));
    for (final t in [...trails, ...dark]) {
      t.dispose();
    }
  });
}
