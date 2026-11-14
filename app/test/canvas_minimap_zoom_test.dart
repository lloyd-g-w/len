import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/features/editor/canvas/canvas_minimap.dart';
import 'package:len/features/editor/canvas/minimap_controls.dart';
import 'package:len/features/editor/canvas/minimap_painter.dart';

import 'canvas_minimap_test.dart'
    show canvasNav, closeMinimapCanvas, minimapPaint, onMinimap, pumpMinimapCanvas;

// The minimap's miniature (and its detail while the map is zoomed), the
// canvas zooms from it (buttons, double tap, corners), folding and sizes. The canvas: waves at (100, 200),
// (3000, 1500) and (-1800, 2600), each 400 wide.

const _waves = [Offset(100, 200), Offset(3000, 1500), Offset(-1800, 2600)];

MinimapPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(minimapPaint).painter! as MinimapPainter;

Finder _button(String tip) =>
    find.descendant(of: find.byType(CanvasMinimap), matching: find.byTooltip(tip));

void main() {
  testWidgets('draws a miniature of the content, not blocks', (tester) async {
    await pumpMinimapCanvas(tester);
    await tester.pump(CanvasMinimap.rasterDelay);
    final painter = _painter(tester);
    expect(painter.raster?.overview, isNotNull);
    expect(painter.lastBlocks, 0);
    await closeMinimapCanvas(tester);
  });

  testWidgets('zoomed in, the map draws a sharper image of the part it shows', (tester) async {
    await pumpMinimapCanvas(tester);
    final nav = canvasNav(tester);
    final scale = nav.viewport.scale;
    final whole = _painter(tester).frame();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(minimapPaint),
        scrollDelta: const Offset(0, -200),
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(nav.viewport.scale, scale, reason: 'the canvas keeps its zoom');
    final frame = _painter(tester).frame();
    expect(frame.width, lessThan(whole.width * 0.9));
    await tester.pump(CanvasMinimap.rasterDelay);
    await tester.pumpAndSettle();
    expect(_painter(tester).raster!.detail?.world, frame);

    // Fitted again: the detail goes.
    await tester.tap(find.byTooltip(CanvasMinimap.fitLabel));
    await tester.pumpAndSettle();
    await tester.pump(CanvasMinimap.rasterDelay);
    await tester.pumpAndSettle();
    expect(_painter(tester).raster!.detail, isNull);
    await closeMinimapCanvas(tester);
  });

  testWidgets('its buttons zoom the canvas out and in and fit all the content', (tester) async {
    await pumpMinimapCanvas(tester);
    final nav = canvasNav(tester);
    final scale = nav.viewport.scale;
    await tester.tap(_button('Zoom in'));
    await tester.pumpAndSettle();
    expect(nav.viewport.scale, greaterThan(scale));
    await tester.tap(_button('Zoom out'));
    await tester.pumpAndSettle();
    await tester.tap(_button('Zoom out'));
    await tester.pumpAndSettle();
    expect(nav.viewport.scale, lessThan(scale));

    nav.zoomTo(4);
    await tester.pumpAndSettle();
    nav.centreOn(const Offset(20000, -9000));
    await tester.pumpAndSettle();
    await tester.tap(_button('Fit content'));
    await tester.pumpAndSettle();
    for (final at in _waves) {
      expect(nav.visibleArea.contains(at), isTrue, reason: '$at');
    }
    await closeMinimapCanvas(tester);
  });

  testWidgets('dragging a corner of the frame zooms the canvas, the opposite corner kept', (
    tester,
  ) async {
    await pumpMinimapCanvas(tester);
    final nav = canvasNav(tester);
    nav.zoomTo(0.25); // A frame large enough for handles.
    await tester.pumpAndSettle();
    final view = nav.visibleArea;
    final corner = onMinimap(tester, view.bottomRight);
    expect(
      MinimapPainter.hasHandles(Rect.fromPoints(onMinimap(tester, view.topLeft), corner)),
      isTrue,
    );

    final drag = await tester.startGesture(corner - const Offset(1, 1));
    for (var i = 0; i < 6; i++) {
      await drag.moveBy(const Offset(5, 3));
      await tester.pump();
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(nav.viewport.scale, lessThan(0.25 * 0.9), reason: 'a larger frame: zoomed out');
    final after = nav.visibleArea;
    expect((after.topLeft - view.topLeft).distance, lessThan(view.width * 0.02));
    expect(after.width / after.height, closeTo(view.width / view.height, 0.01));

    // Inwards from the top-left corner: closer, the bottom right kept.
    final tl = onMinimap(tester, after.topLeft);
    final inward = await tester.startGesture(tl + const Offset(1, 1));
    for (var i = 0; i < 6; i++) {
      await inward.moveBy(const Offset(4, 2.5));
      await tester.pump();
    }
    await inward.up();
    await tester.pumpAndSettle();
    final closer = nav.visibleArea;
    expect(closer.width, lessThan(after.width * 0.9));
    expect((closer.bottomRight - after.bottomRight).distance, lessThan(after.width * 0.02));
    await closeMinimapCanvas(tester);
  });

  testWidgets('a double tap zooms in there', (tester) async {
    await pumpMinimapCanvas(tester);
    final nav = canvasNav(tester);
    final scale = nav.viewport.scale;
    final at = onMinimap(tester, const Offset(3200, 1500));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(nav.viewport.scale, greaterThan(scale));
    expect((nav.visibleArea.center - const Offset(3200, 1500)).distance, lessThan(60));
    await closeMinimapCanvas(tester);
  });

  testWidgets('folds into a button and back, remembered', (tester) async {
    final services = await pumpMinimapCanvas(tester);
    await tester.tap(_button('Fold minimap'));
    await tester.pumpAndSettle();
    expect(minimapPaint, findsNothing);
    expect(find.byType(MinimapFoldedButton), findsOneWidget);
    expect(services.settings.minimapCollapsed, isTrue);
    await tester.tap(find.byTooltip('Show minimap'));
    await tester.pumpAndSettle();
    expect(minimapPaint, findsOneWidget);
    expect(services.settings.minimapCollapsed, isFalse);
    await closeMinimapCanvas(tester);
  });

  testWidgets('opens folded when left folded', (tester) async {
    await pumpMinimapCanvas(tester, before: (s) => s.settings.minimapCollapsed = true);
    expect(find.byType(MinimapFoldedButton), findsOneWidget);
    expect(minimapPaint, findsNothing);
    await closeMinimapCanvas(tester);
  });

  testWidgets('its menu picks its size, remembered', (tester) async {
    final services = await pumpMinimapCanvas(tester);
    expect(tester.getSize(minimapPaint).width, CanvasMinimap.sides[MinimapScale.medium]);
    await tester.longPressAt(tester.getCenter(minimapPaint));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Large'));
    await tester.pumpAndSettle();
    expect(services.settings.minimapScale, MinimapScale.large);
    expect(tester.getSize(minimapPaint).width, CanvasMinimap.sides[MinimapScale.large]);
    expect(find.text('Large'), findsNothing, reason: 'the menu closed');
    await closeMinimapCanvas(tester);
  });
}
