import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/tools/laser_options_panel.dart';
import 'package:len/ink/render/laser_painter.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/laser.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/ui/app_theme.dart';

import 'content_golden_test.dart' show loadFonts;

/// A trail drawn over 1.2 s (a loop then a wave), seen 1.2 s after it began.
LaserTrail sampleTrail(LaserConfig config, Offset origin) {
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
    i == 0 ? trail.down(p) : trail.move(p);
    trail.tick(t * 1200);
  }
  return trail;
}

void main() {
  testWidgets('laser pointer: trail and dot, colours, options panel', (tester) async {
    await loadFonts();
    tester.view
      ..physicalSize = const Size(980, 560)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final viewport = ViewportController();
    addTearDown(viewport.dispose);
    final configs = [
      const LaserConfig(),
      const LaserConfig(color: 0xFF2BD957, size: 9),
      const LaserConfig(color: 0xFF2F8BFF, size: 4),
      const LaserConfig(mode: LaserMode.dot, size: 10),
    ];
    final trails = [
      for (final (i, c) in configs.indexed)
        sampleTrail(c, Offset(20.0 + (i % 2) * 330, 10.0 + (i ~/ 2) * 130)),
    ];
    // Same strokes on dark paper (bottom half).
    final dark = [
      for (final (i, c) in configs.indexed)
        sampleTrail(c, Offset(20.0 + (i % 2) * 330, 10.0 + (i ~/ 2) * 130)),
    ];
    final tools = ToolSettings()..laser = const LaserConfig(color: 0xFF2BD957, size: 9);
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
