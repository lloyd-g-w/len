import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/canvas/canvas_minimap.dart';
import 'package:len/features/editor/canvas/canvas_navigation.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/ui/app_theme.dart';

/// Lines of scribbled words from [at], [width] wide, in [color].
List<Stroke> _words(
  String prefix,
  Offset at, {
  int lines = 4,
  double width = 900,
  int color = 0xFF1F2937,
}) {
  final rnd = math.Random(prefix.hashCode);
  return [
    for (var line = 0; line < lines; line++)
      for (var x = 0.0; x < width - 80; x += 110)
        Stroke(
          id: '$prefix$line-$x',
          surfaceId: 's',
          tool: InkTool.ballpoint,
          color: color,
          width: 4,
          points: [
            for (var t = 0.0; t < 70 + rnd.nextDouble() * 20; t += 3)
              StrokePoint(at.dx + x + t, at.dy + line * 90 + math.sin(t / 5 + x) * 14, 0.5),
          ],
          createdAt: 1,
        ),
  ];
}

Stroke _highlight(Offset at, double width) => Stroke(
  id: 'hl$at',
  surfaceId: 's',
  tool: InkTool.highlighter,
  color: 0xFFFFD43B,
  width: 60,
  points: [for (var t = 0.0; t <= width; t += 20) StrokePoint(at.dx + t, at.dy, 0.5)],
  createdAt: 0,
);

Stroke _box(Rect r, int color) => Stroke(
  id: 'box$r',
  surfaceId: 's',
  tool: InkTool.ballpoint,
  color: color,
  width: 12,
  points: [
    for (final p in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft, r.topLeft])
      StrokePoint(p.dx, p.dy, 0.5),
  ],
  createdAt: 2,
);

/// One minimap over a canvas of [paper] in [theme], the view at [view].
Widget _map(
  StrokeRepository repo,
  ThemeData theme,
  PaperColor paper, {
  required Offset view,
  double scale = 0.5,
}) {
  final model = SurfaceModel(surfaceId: 's', repository: repo);
  final viewport = ViewportController()..setSize(const Size(1200, 800));
  final nav = CanvasNavigation(viewport: viewport, reader: repo, surfaceId: 's');
  viewport.setView(scale: scale, offset: const Offset(600, 400) - view * scale);
  return Theme(
    data: theme,
    child: ColoredBox(
      color: paper.paper,
      child: Padding(
        padding: const EdgeInsets.all(Gaps.lg),
        child: Align(
          alignment: Alignment.bottomRight,
          child: CanvasMinimap(
            navigation: nav,
            model: model,
            live: LiveInk(),
            paperColor: paper,
            size: const Size(264, 165),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('minimap: a miniature in colour, the view clear and framed, light and dark', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(600, 660)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final repo = StrokeRepository(db, deviceId: 'd');
    repo.save([
      _highlight(const Offset(-20, 0), 700),
      ..._words('a', Offset.zero),
      ..._words('b', const Offset(2600, 900), lines: 6, width: 1400, color: 0xFF1C4ED8),
      ..._words('c', const Offset(-2200, 2200), lines: 3, color: 0xFFE03131),
      _box(const Rect.fromLTWH(1200, 2400, 900, 600), 0xFF2F9E44),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        debugShowCheckedModeBanner: false,
        home: Column(
          children: [
            Expanded(
              child: _map(repo, AppTheme.light(), PaperColor.cream, view: const Offset(500, 300)),
            ),
            Expanded(
              child: _map(repo, AppTheme.dark(), PaperColor.dark, view: const Offset(3300, 1300)),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(CanvasMinimap.rasterDelay);
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/canvas_minimap.png'));
    await tester.pumpWidget(const SizedBox());
  });
}
