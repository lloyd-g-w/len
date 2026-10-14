import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/canvas/canvas_minimap.dart';
import 'package:len/features/editor/canvas/canvas_navigation.dart';
import 'package:len/features/editor/canvas/canvas_view.dart';
import 'package:len/features/editor/canvas/minimap_geometry.dart';
import 'package:len/features/editor/canvas/minimap_painter.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/chrome_fade.dart';

import 'content_tools_ui_test.dart' show pinCanvasView;

Stroke _wave(String id, String surface, Offset at) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF1F2937,
  width: 5,
  points: [
    for (var i = 0; i < 40; i++)
      StrokePoint(at.dx + i * 10.0, at.dy + 30 * (i.isEven ? 1 : -1) * (i / 40), 0.5),
  ],
  createdAt: 1,
);

/// A canvas with ink in three far-apart places and the minimap on.
Future<AppServices> _pumpCanvas(WidgetTester tester, {bool minimap = true}) async {
  tester.view
    ..physicalSize = const Size(1000, 700)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = AppServices.create(AppDatabase.inMemory());
  addTearDown(services.dispose);
  services.settings.canvasMinimap = minimap;
  final nb = services.notebooks.create(
    title: 'Board',
    kind: NotebookKind.canvas,
    paper: PaperStyle.dotted,
    paperColor: PaperColor.cream,
    coverColor: 0,
  );
  services.strokes.save([
    _wave('a', nb.id, const Offset(100, 200)),
    _wave('b', nb.id, const Offset(3000, 1500)),
    _wave('c', nb.id, const Offset(-1800, 2600)),
  ]);
  pinCanvasView(services, nb.id, const Size(1000, 700));
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
  return services;
}

CanvasNavigation _nav(WidgetTester tester) =>
    tester.widget<CanvasView>(find.byType(CanvasView)).navigation;

final _mapPaint = find.descendant(
  of: find.byType(CanvasMinimap),
  matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is MinimapPainter),
);

/// Where world point [world] is on screen, on the map.
Offset _onMap(WidgetTester tester, Offset world) {
  final paint = tester.widget<CustomPaint>(_mapPaint);
  final painter = paint.painter! as MinimapPainter;
  final box = tester.getRect(_mapPaint);
  return box.topLeft + MinimapProjection(painter.frame(), box.size).toMap(world);
}

bool _mapShown(WidgetTester tester) => tester
    .widget<ChromeFade>(
      find.descendant(of: find.byType(CanvasMinimap), matching: find.byType(ChromeFade)).first,
    )
    .visible;

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  group('MinimapContent', () {
    test('one block per chunk on a small canvas, denser chunks stronger', () {
      final content = MinimapContent.fromDensity({(x: 0, y: 0): 1, (x: 3, y: 1): 24});
      expect(content.cells, hasLength(2));
      expect(content.cellSize, ChunkGrid.size);
      expect(content.bounds, const Rect.fromLTRB(0, 0, 4 * 512, 2 * 512));
      final weights = {for (final c in content.cells) c.rect.topLeft: c.weight};
      expect(weights[Offset.zero]!, lessThan(weights[const Offset(3 * 512, 512)]!));
      expect(weights[const Offset(3 * 512, 512)], 1);
    });

    test('a vast canvas merges into a bounded number of blocks', () {
      final density = <ChunkKey, int>{
        for (var y = -150; y < 150; y++)
          for (var x = -400; x < 400; x += 2) (x: x, y: y): 3,
      };
      final content = MinimapContent.fromDensity(density);
      expect(density.length, 120000);
      expect(content.cells.length, lessThanOrEqualTo(48 * 48));
      expect(content.bounds!.width, 800 * ChunkGrid.size - ChunkGrid.size);
      // Every chunk lies in some block.
      for (final key in [(x: -400, y: -150), (x: 398, y: 149)]) {
        final centre = ChunkGrid.rectOf(key).center;
        expect(content.cells.any((c) => c.rect.contains(centre)), isTrue);
      }
    });

    test('empty', () {
      expect(MinimapContent.fromDensity(const {}).isEmpty, isTrue);
    });
  });

  group('MinimapFrame', () {
    const content = Rect.fromLTWH(0, 0, 3000, 2000);

    test('shows content and view with room, at the aspect asked', () {
      const view = Rect.fromLTWH(4000, 0, 1000, 700);
      final frame = MinimapFrame.next(content: content, view: view, aspect: 1.5);
      expect(frame.contains(content.topLeft) && frame.contains(view.bottomRight), isTrue);
      expect(frame.width / frame.height, closeTo(1.5, 1e-9));
    });

    test('holds still while the view moves inside it, refits when it leaves', () {
      const view = Rect.fromLTWH(100, 100, 1000, 700);
      final first = MinimapFrame.next(content: content, view: view);
      final panned = MinimapFrame.next(
        previous: first,
        content: content,
        view: view.shift(const Offset(300, 200)),
      );
      expect(panned, first);
      final away = MinimapFrame.next(
        previous: first,
        content: content,
        view: view.shift(const Offset(9000, 0)),
      );
      expect(away, isNot(first));
      expect(away.contains(const Offset(9500, 400)), isTrue);
    });

    test('shrinks back once it is far larger than needed', () {
      const view = Rect.fromLTWH(100, 100, 1000, 700);
      final huge = MinimapFrame.next(
        content: content,
        view: const Rect.fromLTWH(-1e5, -1e5, 2e5, 2e5),
      );
      final back = MinimapFrame.next(previous: huge, content: content, view: view);
      expect(back.width, lessThan(huge.width / 10));
    });

    test('projection maps back and forth', () {
      final p = MinimapProjection(const Rect.fromLTWH(-500, 0, 3000, 2000), const Size(150, 100));
      expect(p.scale, 0.05);
      expect(p.toMap(const Offset(-500, 0)), Offset.zero);
      expect(
        p.toWorld(p.toMap(const Offset(1234, 567))),
        within(distance: 1e-9, from: const Offset(1234, 567)),
      );
    });
  });

  test('minimapSize follows the free area within limits', () {
    expect(minimapSize(const Size(1600, 1000)), const Size(176, 110));
    expect(minimapSize(const Size(400, 800), phone: true), const Size(96, 128));
    expect(minimapSize(const Size(3000, 1000)).aspectRatio, closeTo(1.6, 1e-9));
  });

  testWidgets('painting a vast canvas draws a bounded number of blocks', (tester) async {
    final density = <ChunkKey, int>{
      for (var y = 0; y < 300; y++)
        for (var x = 0; x < 300; x++) (x: x, y: y): 1,
    };
    final painter = MinimapPainter(
      content: MinimapContent.fromDensity(density),
      frame: () => const Rect.fromLTWH(0, 0, 300 * 512, 300 * 512),
      view: () => const Rect.fromLTWH(0, 0, 1000, 700),
      colors: const MinimapColors(
        paper: Color(0xFFFFFFFF),
        ink: Color(0xFF000000),
        view: Color(0xFF1C4ED8),
      ),
      repaint: const AlwaysStoppedAnimation(0),
    );
    final recorder = PictureRecorder();
    painter.paint(Canvas(recorder), const Size(176, 117));
    recorder.endRecording().dispose();
    expect(painter.lastBlocks, lessThanOrEqualTo(48 * 48));
  });

  group('CanvasMinimap', () {
    testWidgets('off by default; ⋯ → View → Minimap and Shift+M toggle it, remembered', (
      tester,
    ) async {
      final services = await _pumpCanvas(tester, minimap: false);
      expect(find.byType(CanvasMinimap), findsNothing);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Minimap'));
      await tester.pumpAndSettle();
      expect(find.byType(CanvasMinimap), findsOneWidget);
      expect(services.settings.canvasMinimap, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.byType(CanvasMinimap), findsNothing);
      expect(services.settings.canvasMinimap, isFalse);
      await _close(tester);
    });

    testWidgets('sits clear of the chrome, shows content and the view', (tester) async {
      await _pumpCanvas(tester);
      expect(_mapShown(tester), isTrue);
      final map = tester.getRect(find.byType(CanvasMinimap));
      final nav = _nav(tester);
      expect(map.bottom, lessThanOrEqualTo(700 - nav.insets.bottom));
      expect(map.top, greaterThan(nav.insets.top));
      expect(map.right, lessThan(1000));
      // All three waves are inside the frame.
      final painter = tester.widget<CustomPaint>(_mapPaint).painter! as MinimapPainter;
      final frame = painter.frame();
      for (final at in const [Offset(100, 200), Offset(3000, 1500), Offset(-1800, 2600)]) {
        expect(frame.contains(at), isTrue);
      }
      expect(frame.contains(nav.visibleArea.center), isTrue);
      await _close(tester);
    });

    testWidgets('tap glides there; dragging the frame pans live', (tester) async {
      await _pumpCanvas(tester);
      final nav = _nav(tester);
      final scale = nav.viewport.scale;
      await tester.tapAt(_onMap(tester, const Offset(3200, 1500)));
      await tester.pump(const Duration(milliseconds: 50));
      expect((nav.visibleArea.center - const Offset(3200, 1500)).distance, greaterThan(100));
      await tester.pumpAndSettle();
      expect((nav.visibleArea.center - const Offset(3200, 1500)).distance, lessThan(30));
      expect(nav.viewport.scale, scale);

      // Grab the frame off-centre: the grabbed point follows the finger.
      final centre = nav.visibleArea.center;
      final grabAt = _onMap(tester, centre + const Offset(150, 100));
      final before = _onMap(tester, Offset.zero);
      final drag = await tester.startGesture(grabAt);
      await drag.moveBy(const Offset(10, 0));
      await tester.pump();
      await drag.moveBy(const Offset(20, 10));
      await tester.pump();
      // The map holds still under the finger while dragging.
      expect(_onMap(tester, Offset.zero), before);
      final moved = _onMap(tester, nav.visibleArea.center + const Offset(150, 100));
      expect((moved - (grabAt + const Offset(30, 10))).distance, lessThan(1));
      await drag.up();
      await tester.pumpAndSettle();
      await _close(tester);
    });

    testWidgets('scroll and pinch on it zoom the canvas', (tester) async {
      await _pumpCanvas(tester);
      final nav = _nav(tester);
      final scale = nav.viewport.scale;
      final centre = tester.getCenter(_mapPaint);
      await tester.sendEventToBinding(
        PointerScrollEvent(position: centre, scrollDelta: const Offset(0, 40)),
      );
      await tester.pumpAndSettle();
      expect(nav.viewport.scale, lessThan(scale));
      final out = nav.viewport.scale;
      final a = await tester.startGesture(centre - const Offset(20, 0));
      final b = await tester.startGesture(centre + const Offset(20, 0), pointer: 2);
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await a.moveBy(const Offset(-6, 0));
        await b.moveBy(const Offset(6, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      expect(nav.viewport.scale, greaterThan(out * 1.5));
      await _close(tester);
    });

    testWidgets('steps aside while writing, back after a pause', (tester) async {
      await _pumpCanvas(tester);
      final pen = await tester.startGesture(const Offset(300, 400), kind: PointerDeviceKind.stylus);
      for (var i = 0; i < 10; i++) {
        await pen.moveBy(const Offset(8, 3));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_mapShown(tester), isFalse);
      await pen.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_mapShown(tester), isFalse);
      await tester.pump(CanvasMinimap.afterWriting);
      await tester.pumpAndSettle();
      expect(_mapShown(tester), isTrue);
      await _close(tester);
    });

    testWidgets('hidden in focus mode unless kept there; its menu hides it', (tester) async {
      final services = await _pumpCanvas(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      expect(_mapShown(tester), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      expect(_mapShown(tester), isTrue);

      // Long-press: keep it in focus mode.
      await tester.longPressAt(tester.getCenter(_mapPaint));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep in focus mode'));
      await tester.pumpAndSettle();
      expect(services.settings.minimapInFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      expect(_mapShown(tester), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();

      // Right-click: hide it.
      await tester.tapAt(tester.getCenter(_mapPaint), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide minimap'));
      await tester.pumpAndSettle();
      expect(find.byType(CanvasMinimap), findsNothing);
      expect(services.settings.canvasMinimap, isFalse);
      await _close(tester);
    });

    testWidgets('an empty canvas shows no map until there is ink', (tester) async {
      tester.view
        ..physicalSize = const Size(1000, 700)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final services = AppServices.create(AppDatabase.inMemory());
      addTearDown(services.dispose);
      services.settings.canvasMinimap = true;
      final nb = services.notebooks.create(
        title: 'Empty',
        kind: NotebookKind.canvas,
        paper: PaperStyle.dotted,
        coverColor: 0,
      );
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
      expect(_mapShown(tester), isFalse);
      final pen = await tester.startGesture(const Offset(300, 400), kind: PointerDeviceKind.stylus);
      for (var i = 0; i < 10; i++) {
        await pen.moveBy(const Offset(8, 3));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await pen.up();
      await tester.pump(CanvasMinimap.refreshDelay + CanvasMinimap.afterWriting);
      await tester.pumpAndSettle();
      expect(_mapShown(tester), isTrue);
      await _close(tester);
    });
  });
}
