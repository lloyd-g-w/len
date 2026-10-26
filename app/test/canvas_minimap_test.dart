import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_reader.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/chunk_digest.dart';
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
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/viewport.dart';
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

/// The world area the map shows.
Rect _shown(WidgetTester tester) =>
    (tester.widget<CustomPaint>(_mapPaint).painter! as MinimapPainter).frame();

/// Map pixels per world unit.
double _mapScale(WidgetTester tester) =>
    MinimapProjection(_shown(tester), tester.getSize(_mapPaint)).scale;

/// The world point under [screen], on the map.
Offset _toWorld(WidgetTester tester, Offset screen) => MinimapProjection(
  _shown(tester),
  tester.getSize(_mapPaint),
).toWorld(screen - tester.getTopLeft(_mapPaint));

/// The canvas's viewport: scale and offset.
(double, Offset) _viewOf(CanvasNavigation nav) => (nav.viewport.scale, nav.viewport.offset);

bool _contains(Rect outer, Rect inner) {
  final o = outer.inflate(1e-6);
  return o.left <= inner.left &&
      o.top <= inner.top &&
      o.right >= inner.right &&
      o.bottom >= inner.bottom;
}

bool _fitButtonShown(WidgetTester tester) => tester
    .widget<ChromeFade>(
      find
          .ancestor(of: find.byTooltip(CanvasMinimap.fitLabel), matching: find.byType(ChromeFade))
          .first,
    )
    .visible;

/// Two fingers about [at] moving apart by [spread] each step (negative:
/// together).
Future<void> _pinch(WidgetTester tester, Offset at, {required double spread}) async {
  final a = await tester.startGesture(at - const Offset(20, 0), pointer: 7);
  final b = await tester.startGesture(at + const Offset(20, 0), pointer: 8);
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await a.moveBy(Offset(-spread / 2, 0));
    await b.moveBy(Offset(spread / 2, 0));
    await tester.pump();
  }
  await a.up();
  await b.up();
  await tester.pumpAndSettle();
}

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

  group('MinimapView', () {
    const fit = Rect.fromLTWH(0, 0, 3000, 2000);
    const size = Size(150, 100);

    test('zooms about a point, between the fit and the closest zoom', () {
      final p = MinimapProjection(fit, size);
      final at = p.toMap(const Offset(900, 600));
      final closer = MinimapView.transform(
        fit,
        size: size,
        fit: fit,
        maxZoom: 4,
        from: at,
        to: at,
        factor: 2,
      );
      expect(closer.width, 1500);
      expect(
        MinimapProjection(closer, size).toMap(const Offset(900, 600)),
        within(distance: 1e-9, from: at),
      );
      final closest = MinimapView.transform(
        closer,
        size: size,
        fit: fit,
        maxZoom: 4,
        from: at,
        to: at,
        factor: 100,
      );
      expect(closest.width, 750);
      final out = MinimapView.transform(
        closer,
        size: size,
        fit: fit,
        maxZoom: 4,
        from: at,
        to: at,
        factor: 0.01,
      );
      expect(out, fit);
    });

    test('pans within the fit', () {
      const shown = Rect.fromLTWH(1000, 500, 1500, 1000);
      final panned = MinimapView.transform(
        shown,
        size: size,
        fit: fit,
        maxZoom: 4,
        from: const Offset(80, 50),
        to: const Offset(70, 50),
      );
      expect(panned, const Rect.fromLTWH(1100, 500, 1500, 1000));
      final far = MinimapView.transform(
        shown,
        size: size,
        fit: fit,
        maxZoom: 4,
        from: const Offset(500, 50),
        to: Offset.zero,
      );
      expect(far.right, fit.right);
    });

    test('follows the view just enough to keep its centre in', () {
      const shown = Rect.fromLTWH(0, 0, 1500, 1000);
      const inside = Rect.fromLTWH(500, 300, 200, 100);
      expect(MinimapView.follow(shown, fit, inside), shown);
      final moved = MinimapView.follow(shown, fit, inside.shift(const Offset(1000, 0)));
      expect(moved.top, 0);
      expect(moved.right, closeTo(1600 + 1000 * MinimapView.followInset, 1e-9));
      expect(MinimapView.tracks(moved, inside.shift(const Offset(1000, 0))), isTrue);
    });
  });

  test('minimapSize follows the free area within limits', () {
    expect(minimapSize(const Size(1600, 1000)), const Size(176, 110));
    expect(minimapSize(const Size(400, 800), phone: true), const Size(120, 120));
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

    testWidgets('a semantics node of its own, never merged into the editor\'s', (tester) async {
      // Merged into the editor's focused node (the walk-through saw it with
      // two tabs open and a tip shown), the map made the whole editor a
      // tappable "Minimap" with the tip in its label; on the web that node
      // then lay over the whole canvas, and no Minimap button was left.
      final semantics = tester.ensureSemantics();
      await _pumpCanvas(tester);
      final label = find.descendant(
        of: find.byType(CanvasMinimap),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Minimap'),
      );
      expect(tester.widget<Semantics>(label).container, isTrue);
      final map = tester.getSemantics(_mapPaint);
      expect(map.label, 'Minimap');
      expect(map.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(map.rect.size, tester.getSize(_mapPaint));
      semantics.dispose();
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

    testWidgets('a pinch zooms the map about the fingers, never the canvas', (tester) async {
      await _pumpCanvas(tester);
      final nav = _nav(tester);
      final view = _viewOf(nav);
      final before = _mapScale(tester);
      final centre = tester.getCenter(_mapPaint);
      // The world point between the fingers stays between them (about the
      // map's centre it would move 20 × (zoom − 1) px; the fingers' first
      // wobble, at the fit, can't pan it).
      final focal = centre + const Offset(20, 0);
      final world = _toWorld(tester, focal);
      await _pinch(tester, focal, spread: 12);
      expect(_mapScale(tester), greaterThan(before * 1.5));
      expect((_onMap(tester, world) - focal).distance, lessThan(6));
      expect(_viewOf(nav), view);
      expect(_fitButtonShown(tester), isTrue);

      // Ctrl+wheel and the trackpad's pinch zoom it too.
      final zoomed = _mapScale(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(position: focal, scrollDelta: const Offset(0, 100)),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(_mapScale(tester), lessThan(zoomed));
      final out = _mapScale(tester);
      final pad = TestPointer(9, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pad.panZoomStart(focal));
      for (final scale in [1.1, 1.2, 1.4, 1.6, 1.8]) {
        await tester.sendEventToBinding(pad.panZoomUpdate(focal, scale: scale));
      }
      await tester.sendEventToBinding(pad.panZoomEnd());
      await tester.pump();
      expect(_mapScale(tester), greaterThan(out * 1.4));
      expect(_viewOf(nav), view);
      await _close(tester);
    });

    testWidgets('zoomed out no further than everything, in no further than a few blocks', (
      tester,
    ) async {
      await _pumpCanvas(tester);
      final fit = _shown(tester);
      final centre = tester.getCenter(_mapPaint);
      await _pinch(tester, centre, spread: -3);
      expect(_shown(tester), fit);
      expect(_fitButtonShown(tester), isFalse);
      for (var i = 0; i < 4; i++) {
        await _pinch(tester, centre, spread: 14);
      }
      final shown = _shown(tester);
      expect(shown.width, closeTo(fit.width / MinimapView.maxZoom(fit, 512), 1e-6));
      expect(_contains(fit, shown), isTrue);
      await _close(tester);
    });

    testWidgets('the wheel and two fingers pan the map, never the canvas', (tester) async {
      await _pumpCanvas(tester);
      final nav = _nav(tester);
      final view = _viewOf(nav);
      final centre = tester.getCenter(_mapPaint);
      await _pinch(tester, centre, spread: 12);
      final zoomed = _shown(tester);
      final scale = _mapScale(tester);

      // Wheel down: the map shows what lies below.
      await tester.sendEventToBinding(
        PointerScrollEvent(position: centre, scrollDelta: const Offset(0, 20)),
      );
      await tester.pump();
      final wheeled = _shown(tester);
      expect(wheeled.top - zoomed.top, closeTo(20 / scale, 1e-6));
      expect(wheeled.left, zoomed.left);

      // Two fingers drag the map along with them.
      // (Each finger moves on its own: the pinch wobbles, and evens out.)
      final a = await tester.startGesture(centre - const Offset(30, 0));
      final b = await tester.startGesture(centre + const Offset(30, 0), pointer: 2);
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        await a.moveBy(const Offset(2, 0));
        await b.moveBy(const Offset(2, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      final dragged = _shown(tester);
      expect(dragged.width, closeTo(wheeled.width, wheeled.width * 0.05));
      // The slop takes some of the move; the rest pans the map.
      expect(dragged.left, lessThan(wheeled.left - 10 / scale));

      // A trackpad's two-finger scroll pans it too.
      final pad = TestPointer(9, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pad.panZoomStart(centre));
      for (var y = 10.0; y <= 60; y += 10) {
        await tester.sendEventToBinding(pad.panZoomUpdate(centre, pan: Offset(0, y)));
      }
      await tester.sendEventToBinding(pad.panZoomEnd());
      await tester.pump();
      expect(_shown(tester).top, lessThan(dragged.top));
      expect(_viewOf(nav), view);
      await _close(tester);
    });

    testWidgets('a tap goes to the right place on a zoomed and panned map', (tester) async {
      await _pumpCanvas(tester);
      final nav = _nav(tester);
      final scale = nav.viewport.scale;
      final centre = tester.getCenter(_mapPaint);
      await _pinch(tester, centre + const Offset(30, 10), spread: 10);
      await tester.sendEventToBinding(
        PointerScrollEvent(position: centre, scrollDelta: const Offset(15, 10)),
      );
      await tester.pump();
      const target = Offset(2800, 1400);
      final at = _onMap(tester, target);
      expect(tester.getRect(_mapPaint).contains(at), isTrue);
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect((nav.visibleArea.center - target).distance, lessThan(1));
      expect(nav.viewport.scale, scale);
      await _close(tester);
    });

    testWidgets('dragging the frame on a zoomed map moves the canvas', (tester) async {
      await _pumpCanvas(tester);
      final nav = _nav(tester);
      await _pinch(tester, _onMap(tester, nav.visibleArea.center), spread: 6);
      final shown = _shown(tester);
      final start = nav.visibleArea.center;
      final grab = _onMap(tester, start);
      final drag = await tester.startGesture(grab);
      await drag.moveBy(const Offset(10, 0));
      await tester.pump();
      await drag.moveBy(const Offset(10, 5));
      await tester.pump();
      // The map holds still; the view follows the finger.
      expect(_shown(tester), shown);
      expect(
        (_onMap(tester, nav.visibleArea.center) - (grab + const Offset(20, 5))).distance,
        lessThan(1),
      );
      await drag.up();
      await tester.pumpAndSettle();
      expect(nav.visibleArea.center.dx, greaterThan(start.dx));
      await _close(tester);
    });

    testWidgets('a zoomed map follows the view; panned away, it marks the edge', (tester) async {
      await _pumpCanvas(tester);
      final nav = _nav(tester);
      await _pinch(tester, _onMap(tester, nav.visibleArea.center), spread: 10);
      final shown = _shown(tester);
      // The view walks off the map's area: the map comes along, still zoomed.
      nav.centreOn(nav.visibleArea.center + Offset(shown.width, 0), animate: false);
      await tester.pump();
      final followed = _shown(tester);
      expect(followed.width, shown.width);
      expect(followed.left, greaterThan(shown.left));
      expect(MinimapView.tracks(followed, nav.visibleArea), isTrue);

      // Panned away from the view, the map stays where it was put.
      for (var i = 0; i < 6; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(_mapPaint),
            scrollDelta: const Offset(0, 120),
          ),
        );
      }
      await tester.pump();
      final away = _shown(tester);
      expect(away.overlaps(nav.visibleArea), isFalse);
      nav.viewport.panBy(const Offset(-30, 0));
      await tester.pump();
      expect(_shown(tester), away);
      await _close(tester);
    });

    testWidgets('the fit button and the menu fit the map again', (tester) async {
      await _pumpCanvas(tester);
      final fit = _shown(tester);
      expect(_fitButtonShown(tester), isFalse);
      final centre = tester.getCenter(_mapPaint);
      await _pinch(tester, centre, spread: 10);
      expect(_shown(tester).width, lessThan(fit.width));
      await tester.tap(find.byTooltip(CanvasMinimap.fitLabel));
      await tester.pumpAndSettle();
      expect(_shown(tester), fit);
      expect(_fitButtonShown(tester), isFalse);

      await _pinch(tester, centre, spread: 10);
      await tester.tapAt(centre, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text(CanvasMinimap.fitLabel));
      await tester.pumpAndSettle();
      expect(_shown(tester), fit);
      await _close(tester);
    });

    testWidgets('a pen or a drag on the map neither writes nor selects on the canvas', (
      tester,
    ) async {
      await _pumpCanvas(tester);
      final model = tester.widget<CanvasView>(find.byType(CanvasView)).model;
      final strokes = model.loadedStrokeCount;
      final centre = tester.getCenter(_mapPaint);
      for (final kind in [PointerDeviceKind.stylus, PointerDeviceKind.touch]) {
        final pen = await tester.startGesture(centre - const Offset(30, 10), kind: kind);
        for (var i = 0; i < 8; i++) {
          await pen.moveBy(const Offset(6, 2));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await pen.up();
        await tester.pumpAndSettle();
      }
      expect(model.loadedStrokeCount, strokes);
      expect(_mapShown(tester), isTrue);
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

    testWidgets('hidden in focus mode; its menu hides it', (tester) async {
      final services = await _pumpCanvas(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      expect(_mapShown(tester), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      expect(_mapShown(tester), isTrue);

      // Its menu holds one row (R12-1: no "Keep in focus mode").
      await tester.longPressAt(tester.getCenter(_mapPaint));
      await tester.pumpAndSettle();
      expect(find.text('Keep in focus mode'), findsNothing);
      expect(find.text('Hide minimap'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
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

    testWidgets('its menu stays above and left of the map, clear of a phone\'s bottom bar', (
      tester,
    ) async {
      await _pumpCanvas(tester);
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpAndSettle();
      final map = tester.getRect(_mapPaint);
      expect(map.bottom, lessThan(800 - 48), reason: 'above the phone\'s bottom toolbar');
      // Pressed at its far corner, a menu at the press would hang over the bar.
      await tester.longPressAt(map.bottomRight - const Offset(4, 4));
      await tester.pumpAndSettle();
      final menu = find.ancestor(
        of: find.text('Hide minimap'),
        matching: find.byType(MenuItemButton),
      );
      final row = tester.getRect(menu);
      expect(row.bottom, lessThanOrEqualTo(map.bottom));
      expect(row.right, lessThanOrEqualTo(map.right));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
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

  testWidgets('memory evictions during a long pan do not re-read the map', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final repo = StrokeRepository(db, deviceId: 'd');
    repo.save([for (var i = 0; i < 12; i++) _wave('s$i', 's', Offset(i * 5000.0, 0))]);
    final reader = _CountingReader(repo);
    final model = SurfaceModel(surfaceId: 's', repository: repo, maxLoadedChunks: 2);
    addTearDown(model.dispose);
    final viewport = ViewportController()..setSize(const Size(800, 600));
    final nav = CanvasNavigation(viewport: viewport, reader: reader, surfaceId: 's');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Stack(
          children: [
            CanvasMinimap(
              navigation: nav,
              model: model,
              live: LiveInk(),
              size: const Size(176, 110),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(reader.densityReads, 1);
    // Pan along the ink: chunks load and far ones are evicted.
    var evictions = 0;
    final sub = model.invalidations.listen((_) => evictions++);
    addTearDown(sub.cancel);
    for (var i = 0; i < 12; i++) {
      model.ensureLoaded(Rect.fromLTWH(i * 5000.0, -100, 800, 600));
      await tester.pump(CanvasMinimap.refreshDelay);
    }
    expect(evictions, greaterThan(0));
    expect(model.strokeById('s0'), isNull); // evicted
    expect(reader.densityReads, 1);
    // A real edit still refreshes it.
    model.addStroke(_wave('new', 's', const Offset(200, 3000)));
    await tester.pump(CanvasMinimap.refreshDelay);
    expect(reader.densityReads, 2);
    await tester.pumpWidget(const SizedBox());
  });
}

/// Counts how often the map's content is read from storage.
class _CountingReader implements StrokeReader {
  _CountingReader(this._inner);

  final StrokeReader _inner;
  int densityReads = 0;

  @override
  FutureOr<ChunkLoad> read(String surfaceId, ChunkRange range, {Set<ChunkKey> skip = const {}}) =>
      _inner.read(surfaceId, range, skip: skip);

  @override
  FutureOr<Map<ChunkKey, ChunkDigest>> chunkDigests(String surfaceId, ChunkRange range) =>
      _inner.chunkDigests(surfaceId, range);

  @override
  FutureOr<Map<ChunkKey, int>> chunkDensity(String surfaceId) {
    densityReads++;
    return _inner.chunkDensity(surfaceId);
  }

  @override
  FutureOr<Rect?> contentBounds(String surfaceId) => _inner.contentBounds(surfaceId);
}
