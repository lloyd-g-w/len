import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/canvas/canvas_minimap.dart';
import 'package:len/features/editor/canvas/canvas_view.dart';
import 'package:len/features/editor/canvas/minimap_geometry.dart';
import 'package:len/features/editor/canvas/minimap_painter.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ui/app_theme.dart';

import '../content_tools_ui_test.dart' show pinCanvasView;
import '../support/canvas_fixtures.dart';
import 'support/big_library.dart';

/// The canvas minimap on a 10,000-stroke canvas: what a pan frame and a
/// pen move cost in the editor with the map on and off (widgets rebuilt,
/// render objects painted, time in the harness), and the map's own work
/// (reading the chunk density, merging it, painting it).
///
/// Run: `tool/light.sh flutter test test/perf/minimap_perf_test.dart`.
void main() {
  // Ink over 40,000 × 25,000 (≈ 2,500 chunks), as a big mind map.
  final ink = scribbles(10000, const Rect.fromLTWH(-20000, -12000, 40000, 25000), points: 14);

  for (final minimap in [false, true]) {
    testWidgets('10k strokes: pan and write, minimap ${minimap ? 'on' : 'off'}', (tester) async {
      await _pumpCanvas(tester, ink, minimap: minimap);
      final nav = tester.widget<CanvasView>(find.byType(CanvasView)).navigation;
      if (minimap) expect(find.byType(CanvasMinimap), findsOneWidget);

      Future<String> measure(Future<void> Function(int i) step, int n) async {
        for (var i = 0; i < 20; i++) {
          await step(i); // Warm up.
        }
        var rebuilds = 0;
        final painted = <String, int>{};
        final built = <String, int>{};
        debugOnRebuildDirtyWidget = (e, _) {
          rebuilds++;
          final name = e.widget.runtimeType.toString();
          built[name] = (built[name] ?? 0) + 1;
        };
        debugProfilePaintsEnabled = true;
        debugOnProfilePaint = (r) {
          final name = r.runtimeType.toString();
          painted[name] = (painted[name] ?? 0) + 1;
        };
        final watch = Stopwatch()..start();
        for (var i = 0; i < n; i++) {
          await step(i);
        }
        watch.stop();
        debugOnRebuildDirtyWidget = null;
        debugOnProfilePaint = null;
        debugProfilePaintsEnabled = false;
        final paints = painted.values.fold(0, (a, b) => a + b);
        return '${(rebuilds / n).toStringAsFixed(1)} rebuilds '
            '(${built.entries.where((e) => e.value >= n ~/ 2).map((e) => '${e.key} ${(e.value / n).toStringAsFixed(1)}').join(', ')}), '
            '${(paints / n).toStringAsFixed(1)} paints '
            '(${painted.entries.where((e) => e.value >= n ~/ 2).map((e) => '${e.key} ${(e.value / n).toStringAsFixed(1)}').join(', ')}), '
            '${(watch.elapsedMicroseconds / n / 1000).toStringAsFixed(2)} ms a frame';
      }

      final pan = await measure((i) async {
        nav.viewport.panBy(Offset(-7.3, i.isEven ? -3.1 : 2.9));
        await tester.pump(const Duration(milliseconds: 16));
      }, 120);
      report('MINIMAP ${minimap ? 'on ' : 'off'} pan:   $pan');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      final pen = await tester.startGesture(const Offset(300, 300), kind: PointerDeviceKind.stylus);
      final write = await measure((i) async {
        await pen.moveTo(Offset(300 + (i % 100) * 4.0, 300 + (i ~/ 100) * 30.0 + (i % 7) * 3));
        await tester.pump(const Duration(milliseconds: 8));
      }, 200);
      await pen.up();
      report('MINIMAP ${minimap ? 'on ' : 'off'} write: $write');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    }, timeout: const Timeout(Duration(minutes: 3)));
  }

  testWidgets('10k strokes: the map\'s own work', (tester) async {
    await tester.runAsync(() async {
      final services = AppServices.create(AppDatabase.inMemory());
      final nb = _canvas(services);
      services.strokes.save([for (final s in ink) _on(s, nb.id)]);
      late Map<({int x, int y}), int> density;
      final read = bestUs(() => density = services.strokes.chunkDensity(nb.id));
      late MinimapContent content;
      final merge = bestUs(() => content = MinimapContent.fromDensity(density));
      const size = Size(176, 110);
      final painter = MinimapPainter(
        content: content,
        frame: () => content.bounds!,
        view: () => const Rect.fromLTWH(0, 0, 1280, 800),
        colors: const MinimapColors(
          paper: Color(0xFFFFFFFF),
          ink: Color(0xFF1F2937),
          view: Color(0xFF2B6CB0),
        ),
        repaint: null,
      );
      final paint = bestUs(() {
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), size);
        recorder.endRecording().dispose();
      }, runs: 20);
      report(
        'MINIMAP work: ${density.length} chunks read in ${read / 1000} ms '
        '(chunkDensity, on the reader isolate in the app), merged into '
        '${content.cells.length} blocks in ${merge / 1000} ms, '
        'painted (${painter.lastBlocks} blocks) in ${paint / 1000} ms',
      );
      services.dispose();
    });
  });
}

Notebook _canvas(AppServices services) => services.notebooks.create(
  title: 'Mind map',
  kind: NotebookKind.canvas,
  paper: PaperStyle.dotted,
  coverColor: 0,
);

Stroke _on(Stroke s, String surface) => Stroke(
  id: s.id,
  surfaceId: surface,
  tool: s.tool,
  color: s.color,
  width: s.width,
  points: s.points,
  createdAt: s.createdAt,
  style: s.style,
);

Future<void> _pumpCanvas(WidgetTester tester, List<Stroke> ink, {required bool minimap}) async {
  tester.view
    ..physicalSize = const Size(1280, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = AppServices.create(AppDatabase.inMemory());
  addTearDown(services.dispose);
  services.settings.canvasMinimap = minimap;
  final nb = _canvas(services);
  services.strokes.save([for (final s in ink) _on(s, nb.id)]);
  pinCanvasView(services, nb.id, const Size(1280, 800));
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: EditorScreen(notebook: nb),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await settle(() => true);
}
