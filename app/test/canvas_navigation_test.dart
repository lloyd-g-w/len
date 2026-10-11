import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/canvas/canvas_minimap.dart';
import 'package:len/features/editor/canvas/canvas_navigation.dart';
import 'package:len/features/editor/canvas/canvas_view.dart';
import 'package:len/features/editor/canvas/minimap_painter.dart';
import 'package:len/features/editor/canvas/zoom_indicator.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ink/navigation/kinetic_pan.dart';
import 'package:len/ink/navigation/viewport_animator.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/ui/app_theme.dart';

import 'content_tools_ui_test.dart' show pinCanvasView;

Stroke _wave(String id, String surface, Offset at, {int color = 0xFF1F2937}) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: color,
  width: 5,
  points: [
    for (var i = 0; i < 40; i++)
      StrokePoint(at.dx + i * 10.0, at.dy + 30 * (i.isEven ? 1 : -1) * (i / 40), 0.5),
  ],
  createdAt: 1,
);

/// A canvas with ink in three far-apart places.
Future<(AppServices, Notebook)> _pumpCanvas(WidgetTester tester, {bool minimap = false}) async {
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
    _wave('b', nb.id, const Offset(3000, 1500), color: 0xFF1C7ED6),
    _wave('c', nb.id, const Offset(-1800, 2600), color: 0xFFE03131),
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
  return (services, nb);
}

ViewportController _viewportOf(WidgetTester tester) =>
    tester.widget<ZoomIndicator>(find.byType(ZoomIndicator)).viewport;

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  group('ViewportAnimator', () {
    testWidgets('animated zoom keeps the focal point still', (tester) async {
      final viewport = ViewportController()..setSize(const Size(800, 600));
      final animator = ViewportAnimator(viewport);
      const focal = Offset(200, 150);
      final world = viewport.toWorld(focal);
      animator.zoomTo(2, focal: focal);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(viewport.scale, inExclusiveRange(1, 2));
      expect((viewport.toScreen(world) - focal).distance, lessThan(0.01));
      await tester.pump(ViewportAnimator.zoomDuration);
      expect(viewport.scale, 2);
      expect(animator.isAnimating, isFalse);
      animator.dispose();
    });

    testWidgets('fit shows a rectangle centred and whole', (tester) async {
      final viewport = ViewportController()..setSize(const Size(800, 600));
      final animator = ViewportAnimator(viewport);
      const target = Rect.fromLTWH(1000, 1000, 2000, 500);
      animator.fit(target, padding: 50);
      await tester.pumpAndSettle();
      expect(viewport.scale, closeTo(0.35, 1e-9)); // 700 / 2000
      final shown = viewport.visibleWorld;
      expect(shown.center.dx, closeTo(target.center.dx, 1e-6));
      expect(shown.contains(target.topLeft) && shown.contains(target.bottomRight), isTrue);
      animator.dispose();
    });
  });

  group('KineticPan', () {
    late ViewportController viewport;
    late ViewportAnimator animator;
    late KineticPan kinetic;

    setUp(() {
      viewport = ViewportController()..setSize(const Size(800, 600));
      animator = ViewportAnimator(viewport);
      kinetic = KineticPan(animator);
    });
    tearDown(() => animator.dispose());

    /// Pans 20 px every 10 ms (2000 px/s) for [steps] samples.
    Duration pan(int steps, {Duration start = Duration.zero}) {
      var t = start;
      kinetic.begin();
      for (var i = 0; i < steps; i++) {
        viewport.panBy(const Offset(20, 0));
        t += const Duration(milliseconds: 10);
        kinetic.track(t);
      }
      return t;
    }

    testWidgets('a fling glides on and slows to a stop', (tester) async {
      final end = pan(8);
      final released = viewport.offset.dx;
      kinetic.release(end);
      expect(animator.isAnimating, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final early = viewport.offset.dx - released;
      await tester.pump(const Duration(milliseconds: 100));
      final second = viewport.offset.dx - released - early;
      expect(early, greaterThan(100)); // ~2000 px/s
      expect(second, lessThan(early)); // decelerating
      await tester.pumpAndSettle();
      // Travels v / ln(1 / drag) ≈ 1000 px in total.
      expect(viewport.offset.dx - released, closeTo(1000, 60));
      expect(animator.isAnimating, isFalse);
    });

    testWidgets('no glide when the finger stopped before lifting', (tester) async {
      final end = pan(8);
      kinetic.release(end + const Duration(milliseconds: 200));
      expect(animator.isAnimating, isFalse);
    });

    testWidgets('a pinch does not glide', (tester) async {
      var t = Duration.zero;
      kinetic.begin();
      for (var i = 0; i < 8; i++) {
        viewport
          ..panBy(const Offset(20, 0))
          ..zoomAt(const Offset(400, 300), 1.05);
        t += const Duration(milliseconds: 10);
        kinetic.track(t);
      }
      kinetic.release(t);
      expect(animator.isAnimating, isFalse);
    });

    testWidgets('touching down stops a glide', (tester) async {
      kinetic.release(pan(8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      kinetic.begin();
      final stopped = viewport.offset;
      await tester.pump(const Duration(milliseconds: 100));
      expect(viewport.offset, stopped);
    });
  });

  testWidgets('a middle-button fling on the canvas glides', (tester) async {
    await _pumpCanvas(tester);
    final viewport = _viewportOf(tester);
    final gesture = await tester.startGesture(
      const Offset(500, 350),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    for (var i = 1; i <= 8; i++) {
      await gesture.moveBy(const Offset(-25, 0), timeStamp: Duration(milliseconds: 10 * i));
    }
    await gesture.up(timeStamp: const Duration(milliseconds: 85));
    final released = viewport.offset.dx;
    await tester.pumpAndSettle();
    expect(viewport.offset.dx, lessThan(released - 300));
    await _close(tester);
  });

  testWidgets('zoom shortcuts, indicator presets and fit content', (tester) async {
    await _pumpCanvas(tester);
    final viewport = _viewportOf(tester);
    final indicator = find.byType(ZoomIndicator);
    double opacity() => tester
        .widget<AnimatedOpacity>(
          find.descendant(of: indicator, matching: find.byType(AnimatedOpacity)),
        )
        .opacity;
    expect(opacity(), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(viewport.scale, 1.5);
    expect(opacity(), 1);
    expect(find.text('150%'), findsOneWidget);

    // Tap the indicator while it shows: pick 50 %.
    await tester.tap(find.text('150%'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('50%').last);
    await tester.pumpAndSettle();
    expect(viewport.scale, 0.5);
    await tester.pump(ZoomIndicator.linger);
    await tester.pumpAndSettle();
    expect(opacity(), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pumpAndSettle();
    expect(viewport.scale, 1);

    // Fit content: all three waves on screen.
    await tester.tap(find.byTooltip('Fit content (Shift+1)'));
    await tester.pumpAndSettle();
    final shown = viewport.visibleWorld;
    for (final p in const [Offset(100, 200), Offset(3390, 1500), Offset(-1800, 2600)]) {
      expect(shown.contains(p), isTrue, reason: '$p in $shown');
    }
    expect(viewport.scale, lessThan(0.25));

    // Home: back to the start (on a canvas; paged notebooks go to page 1).
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(viewport.scale, closeTo(1, 1e-9));
    // The origin sits at the top left, below the chrome.
    final insets = tester.widget<CanvasView>(find.byType(CanvasView)).insets;
    expect((viewport.offset - Offset(insets.left, insets.top)).distance, lessThan(0.5));
    expect(insets.top, greaterThan(0));
    await _close(tester);
  });

  testWidgets('minimap: toggle, golden, tap to glide there', (tester) async {
    final (services, _) = await _pumpCanvas(tester);
    final viewport = _viewportOf(tester);
    expect(find.byType(CanvasMinimap), findsNothing);
    await tester.tap(find.byTooltip('Show overview'));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasMinimap), findsOneWidget);
    expect(services.settings.canvasMinimap, isTrue);
    // Zoom out one step (75 %) so the map shows a larger view.
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.pumpAndSettle();
    await expectLater(find.byType(EditorScreen), matchesGoldenFile('goldens/canvas_minimap.png'));

    // Tap where the blue wave is on the map: the view glides to it.
    final box = tester.getRect(find.byType(CanvasMinimap));
    final paint = tester.widget<CustomPaint>(
      find.descendant(of: find.byType(CanvasMinimap), matching: find.byType(CustomPaint)).last,
    );
    final painter = paint.painter! as MinimapPainter;
    final map = MinimapProjection(
      MinimapProjection.extentOf(painter.density.keys, viewport.visibleWorld),
      CanvasMinimap.defaultSize,
    );
    final mapRect = tester.getRect(
      find.descendant(of: find.byType(CanvasMinimap), matching: find.byType(CustomPaint)).last,
    );
    expect(box.contains(mapRect.center), isTrue);
    await tester.tapAt(mapRect.topLeft + map.toMap(const Offset(3200, 1500)));
    await tester.pumpAndSettle();
    expect((viewport.visibleWorld.center - const Offset(3200, 1500)).distance, lessThan(60));
    await _close(tester);
  });

  testWidgets('canvas background: template and paper colour', (tester) async {
    final (services, nb) = await _pumpCanvas(tester);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Background…'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Dark'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dark'));
    await tester.tap(find.text('Use template'));
    await tester.pumpAndSettle();
    expect(services.notebooks.get(nb.id)!.paperColor, PaperColor.dark);
    await _close(tester);
  });

  test('zoom steps are ordered', () {
    const steps = CanvasNavigation.zoomSteps;
    for (var i = 1; i < steps.length; i++) {
      expect(steps[i], greaterThan(steps[i - 1]));
    }
  });
}
