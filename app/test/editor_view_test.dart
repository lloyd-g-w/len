import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/canvas/canvas_view.dart';
import 'package:len/features/editor/document/document_controller.dart';
import 'package:len/features/editor/document/page_fit.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/tabs/open_notebooks.dart';
import 'package:len/ui/app_theme.dart';

/// Where notebooks open: page fit, centred canvases, remembered views.
void main() {
  group('page fit', () {
    const a4 = Size(794, 1123);
    double fit(PageFit f, Size screen, {EdgeInsets insets = EdgeInsets.zero}) =>
        f.scale(screen: screen, insets: insets, width: a4.width, height: a4.height);

    test('automatic fits the width on portrait screens', () {
      const portrait = Size(800, 1280);
      expect(fit(PageFit.auto, portrait), closeTo(fit(PageFit.width, portrait), 1e-9));
      const phone = Size(390, 844);
      expect(fit(PageFit.auto, phone), closeTo((390 - 32) / 794, 1e-9));
    });

    test('automatic keeps most of a page visible on landscape tablets', () {
      const landscape = Size(1280, 800);
      const chrome = EdgeInsets.only(top: 156);
      final scale = fit(PageFit.auto, landscape, insets: chrome);
      final free = 800 - 156 - 32;
      expect(free / (a4.height * scale), greaterThanOrEqualTo(0.55 - 1e-9));
      expect(scale, lessThan(fit(PageFit.width, landscape)));
      expect(scale, greaterThan(fit(PageFit.page, landscape, insets: chrome)));
    });

    test('fit page shows the whole page', () {
      const landscape = Size(1280, 800);
      final scale = fit(PageFit.page, landscape, insets: const EdgeInsets.only(top: 100));
      expect(a4.height * scale, lessThanOrEqualTo(800 - 100 - 32 + 1e-9));
    });
  });

  test('view states round-trip through text', () {
    const view = EditorViewState(
      scale: 1.25,
      offset: Offset(-12.5, 40),
      page: 3,
      size: Size(1280, 800),
      fit: 'page',
    );
    final back = EditorViewState.decode(view.encode())!;
    expect(back.scale, 1.25);
    expect(back.offset, const Offset(-12.5, 40));
    expect(back.page, 3);
    expect(back.size, const Size(1280, 800));
    expect(back.fit, 'page');
    expect(EditorViewState.decode(null), isNull);
    expect(EditorViewState.decode('nonsense'), isNull);
    expect(EditorViewState.decode('0,1,2,3'), isNull); // Zero zoom.
    expect(const EditorViewState(scale: 1, offset: Offset.zero).fitsSize(const Size(1, 1)), isTrue);
  });

  Future<AppServices> pump(WidgetTester tester, Notebook Function(AppServices) create) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    final notebook = create(services);
    await open(tester, services, notebook);
    return services;
  }

  testWidgets('a canvas opens centred on its content, at most at 100 %', (tester) async {
    await pump(tester, (s) {
      final nb = s.notebooks.create(
        title: 'Board',
        kind: NotebookKind.canvas,
        paper: PaperStyle.dotted,
        coverColor: 0,
      );
      s.strokes.save([
        for (final (i, at) in const [Offset(-300, -200), Offset(250, 150)].indexed)
          Stroke(
            id: 's$i',
            surfaceId: nb.id,
            tool: InkTool.ballpoint,
            color: 0xFF1F2937,
            width: 3,
            points: [for (var x = 0.0; x <= 60; x += 6) StrokePoint(at.dx + x, at.dy, 0.5)],
            createdAt: i,
          ),
      ]);
      return nb;
    });
    final view = tester.widget<CanvasView>(find.byType(CanvasView));
    final viewport = view.navigation.viewport;
    expect(viewport.scale, lessThanOrEqualTo(1));
    final free = view.insets.deflateRect(Offset.zero & viewport.size);
    for (final p in const [Offset(-300, -200), Offset(310, 150)]) {
      expect(free.contains(viewport.toScreen(p)), isTrue, reason: '$p');
    }
  });

  testWidgets('page zoom from the menu, remembered when the notebook reopens', (tester) async {
    late Notebook nb;
    final s = await pump(tester, (s) {
      nb = s.notebooks.create(
        title: 'Notes',
        kind: NotebookKind.paged,
        paper: PaperStyle.collegeRuled,
        coverColor: 0,
      );
      s.pages.addPage(nb.id, template: const PageTemplate());
      return nb;
    });
    DocumentController doc() =>
        tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
    expect(doc().fit, PageFit.auto);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    // In the order of their shortcuts (Shift+1, Shift+2, 0).
    final fits = ['Fit page', 'Fit width', 'Automatic zoom'];
    final tops = [for (final f in fits) tester.getTopLeft(find.text(f).last).dy];
    expect(tops, orderedEquals([...tops]..sort()));
    await tester.tap(find.text('Fit page'));
    await tester.pumpAndSettle();
    expect(doc().fit, PageFit.page);
    final page = doc().layout.frameOf(0)!;
    final shown = doc().viewport.visibleWorld;
    expect(shown.contains(page.topLeft) && shown.contains(page.bottomRight), isTrue);

    // Shift+2: fit width, then scroll to page 2.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(doc().fit, PageFit.width);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    final before = doc().viewState;
    expect(before.page, 1);

    // Close and reopen (a new launch: no tab memory).
    await tester.pumpWidget(const SizedBox());
    for (final tab in s.openNotebooks.tabs) {
      s.openNotebooks.close(tab.id);
    }
    await open(tester, s, nb);
    expect(doc().fit, PageFit.width);
    expect(doc().currentPage, 1);
    expect(doc().viewport.scale, closeTo(before.scale, 1e-6));
    expect((doc().viewport.offset - before.offset).distance, lessThan(0.5));
  });

  testWidgets('opens on the page another device wrote on since (R16-4)', (tester) async {
    late Notebook nb;
    late String third;
    await pump(tester, (s) {
      nb = s.notebooks.create(
        title: 'Lecture',
        kind: NotebookKind.paged,
        paper: PaperStyle.collegeRuled,
        coverColor: 0,
      );
      s.pages.addPage(nb.id, template: const PageTemplate());
      third = s.pages.addPage(nb.id, template: const PageTemplate()).id;
      s.strokes.save([
        Stroke(
          id: 'from-tablet',
          createdAt: 1,
          surfaceId: third,
          tool: InkTool.ballpoint,
          color: 0xFF000000,
          width: 2,
          points: const [StrokePoint(100, 100, 0.5), StrokePoint(200, 100, 0.5)],
        ),
      ]);
      s.database.execute("UPDATE strokes SET device_id = 'tablet'");
      return nb;
    });
    final doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
    expect(doc.currentPage, 2);
    final page = doc.layout.frameOf(2)!;
    expect(doc.viewport.visibleWorld.overlaps(page), isTrue);
  });
}

Future<void> open(WidgetTester tester, AppServices services, Notebook notebook) async {
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: EditorScreen(notebook: notebook),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
