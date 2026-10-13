import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/canvas/zoom_indicator.dart';
import 'package:len/features/editor/document/document_controller.dart';
import 'package:len/features/editor/document/document_layout.dart';
import 'package:len/features/editor/document/page_swipe.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ui/app_theme.dart';

import 'content_tools_ui_test.dart' show pinCanvasView;

Duration ms(int v) => Duration(milliseconds: v);

/// A three-page notebook (or a canvas) in the editor, fingers navigating.
Future<AppServices> _pump(
  WidgetTester tester, {
  PageFlow flow = PageFlow.continuous,
  bool canvas = false,
}) async {
  tester.view
    ..physicalSize = const Size(800, 1200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = AppServices.create(AppDatabase.inMemory());
  addTearDown(services.dispose);
  services.preferences.stylusOnly = true;
  services.settings.pageFlow = flow.name;
  final nb = services.notebooks.create(
    title: 'Notes',
    kind: canvas ? NotebookKind.canvas : NotebookKind.paged,
    paper: PaperStyle.collegeRuled,
    coverColor: 0,
    firstPage: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)),
  );
  if (canvas) {
    pinCanvasView(services, nb.id, const Size(800, 1200));
  } else {
    for (var i = 0; i < 2; i++) {
      services.pages.addPage(nb.id, template: const PageTemplate(paper: Paper(PaperStyle.dotted)));
    }
  }
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

DocumentController _doc(WidgetTester tester) =>
    tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// One finger from [from] by [by] in [steps] moves over [duration] ms,
/// starting at [t0] ms.
Future<void> _swipe(
  WidgetTester tester,
  Offset from,
  Offset by, {
  required int duration,
  int steps = 8,
  int t0 = 0,
}) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.touch);
  await g.down(from, timeStamp: ms(t0));
  for (var i = 1; i <= steps; i++) {
    await g.moveTo(from + by * (i / steps), timeStamp: ms(t0 + duration * i ~/ steps));
  }
  await g.up(timeStamp: ms(t0 + duration + 5));
  await tester.pumpAndSettle();
}

/// Two fingers about [centre], [gap] apart, pinching to [gap2].
Future<void> _pinch(WidgetTester tester, Offset centre, double gap, double gap2) async {
  final a = await tester.createGesture(kind: PointerDeviceKind.touch);
  final b = await tester.createGesture(kind: PointerDeviceKind.touch);
  await a.down(centre - Offset(gap / 2, 0), timeStamp: ms(0));
  await b.down(centre + Offset(gap / 2, 0), timeStamp: ms(0));
  const steps = 12;
  for (var i = 1; i <= steps; i++) {
    final g = gap + (gap2 - gap) * i / steps;
    await a.moveTo(centre - Offset(g / 2, 0), timeStamp: ms(16 * i));
    await b.moveTo(centre + Offset(g / 2, 0), timeStamp: ms(16 * i));
  }
  await a.up(timeStamp: ms(16 * steps + 100));
  await b.up(timeStamp: ms(16 * steps + 100));
  await tester.pumpAndSettle();
}

void main() {
  group('PageSwipe', () {
    test('a quick flick turns, even a short one', () {
      expect(PageSwipe.turn(const Offset(-50, 6), ms(100), 800), 1);
      expect(PageSwipe.turn(const Offset(50, -6), ms(100), 800), -1);
    });

    test('a slow drag turns once it crosses a good part of the screen', () {
      expect(PageSwipe.turn(const Offset(-300, 20), ms(1500), 800), 1);
      expect(PageSwipe.turn(const Offset(-120, 0), ms(1500), 800), 0);
    });

    test('a tiny or mostly vertical move does not turn', () {
      expect(PageSwipe.turn(const Offset(-20, 0), ms(30), 800), 0);
      expect(PageSwipe.turn(const Offset(-200, 180), ms(150), 800), 0);
    });
  });

  group('single-page flow', () {
    testWidgets('flicks and long drags turn pages; short drags settle back', (tester) async {
      await _pump(tester, flow: PageFlow.single);
      final doc = _doc(tester);
      final fitted = (doc.viewport.scale, doc.viewport.offset);
      await _swipe(tester, const Offset(500, 600), const Offset(-60, 4), duration: 120);
      expect(doc.currentPage, 1);
      await _swipe(tester, const Offset(200, 600), const Offset(320, 10), duration: 1400);
      expect(doc.currentPage, 0);
      // A hesitant, short drag: the page stays and returns to its place.
      await _swipe(tester, const Offset(400, 600), const Offset(-70, 40), duration: 900);
      expect(doc.currentPage, 0);
      expect(doc.viewport.scale, closeTo(fitted.$1, 1e-6));
      expect((doc.viewport.offset - fitted.$2).distance, lessThan(0.5));
      await _close(tester);
    });

    testWidgets('a pinch below the whole page springs back to it', (tester) async {
      await _pump(tester, flow: PageFlow.single);
      final doc = _doc(tester);
      final fitted = (doc.viewport.scale, doc.viewport.offset);
      await _pinch(tester, const Offset(400, 600), 300, 150);
      expect(doc.viewport.scale, closeTo(fitted.$1, 1e-6));
      expect((doc.viewport.offset - fitted.$2).distance, lessThan(0.5));
      expect(doc.currentPage, 0);
      await _close(tester);
    });

    testWidgets('a wheel flick turns one page; a trackpad swipe turns too', (tester) async {
      await _pump(tester, flow: PageFlow.single);
      final doc = _doc(tester);
      Future<void> wheel(double dy, int t) async {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: const Offset(400, 600),
            scrollDelta: Offset(0, dy),
            timeStamp: ms(t),
          ),
        );
        await tester.pump();
      }

      // One notch turns; the rest of the flick (and its inertia) doesn't.
      for (var i = 0; i < 6; i++) {
        await wheel(53, 1000 + 40 * i);
      }
      await tester.pumpAndSettle();
      expect(doc.currentPage, 1);
      await wheel(-53, 2000);
      await tester.pumpAndSettle();
      expect(doc.currentPage, 0);

      const cursor = Offset(400, 600);
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(pointer: 7, position: cursor, timeStamp: ms(3000)),
      );
      for (var i = 1; i <= 6; i++) {
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(
            pointer: 7,
            position: cursor,
            pan: Offset(-20.0 * i, 0),
            panDelta: const Offset(-20, 0),
            timeStamp: ms(3000 + 16 * i),
          ),
        );
      }
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(pointer: 7, position: cursor, timeStamp: ms(3110)),
      );
      await tester.pumpAndSettle();
      expect(doc.currentPage, 1);
      await _close(tester);
    });

    testWidgets('a palm next to a hovering pen never turns the page', (tester) async {
      await _pump(tester, flow: PageFlow.single);
      final doc = _doc(tester);
      final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
      await pen.addPointer(location: const Offset(300, 300), timeStamp: ms(0));
      await pen.moveTo(const Offset(310, 300), timeStamp: ms(10));
      await _swipe(tester, const Offset(500, 900), const Offset(-150, 0), duration: 100, t0: 50);
      expect(doc.currentPage, 0);
      await pen.removePointer(timeStamp: ms(400));
      await _close(tester);
    });
  });

  group('continuous flow', () {
    testWidgets('a pinch ending near the page fit snaps to it', (tester) async {
      await _pump(tester);
      final doc = _doc(tester);
      final fit = doc.viewport.scale;
      await _pinch(tester, const Offset(400, 600), 300, 300 * 1.05 + 16);
      expect(doc.viewport.scale, closeTo(fit, 1e-6));
      await _pinch(tester, const Offset(400, 600), 200, 400);
      expect(doc.viewport.scale, greaterThan(fit * 1.5));
      await _close(tester);
    });

    testWidgets('the wheel scrolls by its delta', (tester) async {
      await _pump(tester);
      final doc = _doc(tester);
      final before = doc.viewport.offset;
      await tester.sendEventToBinding(
        const PointerScrollEvent(position: Offset(400, 600), scrollDelta: Offset(0, 120)),
      );
      await tester.pump();
      expect(doc.viewport.offset - before, const Offset(0, -120));
      await _close(tester);
    });
  });

  testWidgets('keys scroll and zoom a paged notebook; arrows move a canvas', (tester) async {
    await _pump(tester);
    final doc = _doc(tester);
    final (scale, offset) = (doc.viewport.scale, doc.viewport.offset);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(doc.viewport.offset.dy - offset.dy, closeTo(-0.15 * 1200, 0.5));
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.pumpAndSettle();
    expect(doc.viewport.scale, closeTo(scale * 1.25, 1e-6));
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.pumpAndSettle();
    expect(doc.viewport.scale, closeTo(scale, 1e-6));
    await _close(tester);

    await _pump(tester, canvas: true);
    final viewport = tester.widget<ZoomIndicator>(find.byType(ZoomIndicator)).viewport;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(viewport.offset.dx, closeTo(-0.15 * 800, 0.5));
    await _close(tester);
  });

  testWidgets('on a canvas, a pinch ending near 100 % snaps to it', (tester) async {
    await _pump(tester, canvas: true);
    final viewport = tester.widget<ZoomIndicator>(find.byType(ZoomIndicator)).viewport;
    await _pinch(tester, const Offset(400, 600), 300, 300 * 0.95 - 16);
    expect(viewport.scale, 1);
    await _close(tester);
  });
}
