import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/document/document_controller.dart';
import 'package:len/features/editor/document/page_models.dart';
import 'package:len/features/editor/document/page_overview.dart';
import 'package:len/features/editor/document/page_thumbnail.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ui/app_theme.dart';

import 'support/big_library.dart';

/// A 500-page notebook, years of lectures: every other page a ruled page
/// full of handwriting, the others pages of an imported PDF (not on this
/// device, so they show as missing; their cost here is the page model).
void main() {
  _longSession();
  _overview();
  testWidgets('500 pages: open, go to the end, page overview', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final clock = BenchClock();
    final s = AppServices.create(AppDatabase.inMemory(), clock: clock);
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'Lectures',
      kind: NotebookKind.paged,
      paper: PaperStyle.collegeRuled,
      coverColor: 0,
    );
    final pdf = '${'ef' * 31}01';
    s.database.transaction(() {
      s.pages.insertPages(nb.id, [
        for (var i = 1; i < 500; i++)
          (
            size: const Size(595, 842),
            paper: Paper(PaperStyle.collegeRuled),
            color: PaperColor.white,
            background: i.isOdd ? PageBackground.pdf(blob: pdf, pageIndex: i ~/ 2) : null,
          ),
      ]);
      for (final p in s.pages.pagesOf(nb.id)) {
        if (p.background == null) s.strokes.save(pageOfInk(p.id, clock, lines: 20, seed: 3));
      }
    });
    final strokes = s.database.db.select('SELECT COUNT(*) AS n FROM strokes').first['n'];

    // Warm up (the first editor of a run compiles and loads much).
    final small = s.notebooks.create(
      title: 'Small',
      kind: NotebookKind.paged,
      paper: PaperStyle.collegeRuled,
      coverColor: 0,
    );
    var watch = Stopwatch();
    for (var i = 0; i < 2; i++) {
      watch = Stopwatch()..start();
      await tester.pumpWidget(
        AppScope(
          services: s,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: EditorScreen(notebook: small),
          ),
        ),
      );
      final first = watch.elapsedMilliseconds;
      await tester.pumpAndSettle();
      report('1-page notebook: first frame ${first}ms, settled ${watch.elapsedMilliseconds}ms');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }

    watch = Stopwatch()..start();
    await tester.pumpWidget(
      AppScope(
        services: s,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: EditorScreen(notebook: nb),
        ),
      ),
    );
    final firstFrame = watch.elapsedMilliseconds;
    await tester.pumpAndSettle();
    final opened = watch.elapsedMilliseconds;
    final doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
    expect(doc.pages, hasLength(500));

    // Go to the last page.
    watch.reset();
    doc.goToPage(499);
    await tester.pump();
    final jump = watch.elapsedMilliseconds;
    await tester.pumpAndSettle();
    final jumpSettled = watch.elapsedMilliseconds;
    expect(doc.currentPage, 499);

    // Scroll back through the whole notebook, a screen at a time.
    final frames = <int>[];
    for (var i = 0; i < 60; i++) {
      final frame = Stopwatch()..start();
      await tester.drag(find.byType(PagedDocumentView), const Offset(0, 900));
      await tester.pump(const Duration(milliseconds: 16));
      frames.add(frame.elapsedMilliseconds);
    }
    frames.sort();

    await _closeAndReport(tester, doc, s, (
      strokes: strokes,
      firstFrame: firstFrame,
      opened: opened,
      jump: jump,
      jumpSettled: jumpSettled,
      frames: frames,
    ));
  });
}

/// A 500-page notebook of handwriting.
(AppServices, Notebook) _lectures({int pages = 500, int lines = 20}) {
  final clock = BenchClock();
  final s = AppServices.create(AppDatabase.inMemory(), clock: clock);
  final nb = s.notebooks.create(
    title: 'Lectures',
    kind: NotebookKind.paged,
    paper: PaperStyle.collegeRuled,
    coverColor: 0,
  );
  s.database.transaction(() {
    s.pages.insertPages(nb.id, [
      for (var i = 1; i < pages; i++)
        (
          size: const Size(595, 842),
          paper: Paper(PaperStyle.collegeRuled),
          color: PaperColor.white,
          background: null,
        ),
    ]);
    for (final p in s.pages.pagesOf(nb.id)) {
      s.strokes.save(pageOfInk(p.id, clock, lines: lines, seed: 3));
    }
  });
  return (s, nb);
}

void _overview() {
  testWidgets('500 pages: the page overview renders what is on screen, bounded', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (s, nb) = _lectures();
    addTearDown(s.dispose);
    final watch = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PageOverview(
          currentPage: 0,
          copier: SurfaceCopier(s.strokes, elements: s.elements),
          handlers: OverviewHandlers(
            load: () => s.pages.pagesOf(nb.id),
            move: s.pages.move,
            command: (context, command, page) async {},
          ),
        ),
      ),
    );
    final firstFrame = watch.elapsedMilliseconds;
    await tester.pumpAndSettle();
    final settled = watch.elapsedMilliseconds;
    final rss = ProcessInfo.currentRss;
    final frames = <int>[];
    // One long, fast drag (25,000 px/s), then letting go.
    final drag = await tester.startGesture(tester.getCenter(find.byType(Scrollable).first));
    for (var i = 0; i < 80; i++) {
      final frame = Stopwatch()..start();
      await drag.moveBy(const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 16));
      frames.add(frame.elapsedMilliseconds);
    }
    await drag.up();
    await tester.pumpAndSettle();
    frames.sort();
    final built = find.byType(PageThumbnail, skipOffstage: false).evaluate().length;
    expect(built, lessThan(80), reason: 'a lazy grid');
    report(
      'overview, 500 pages: first frame ${firstFrame}ms, settled ${settled}ms; scroll frames '
      'median ${frames[frames.length ~/ 2]}ms, max ${frames.last}ms; $built thumbnails '
      'built; RSS +${(ProcessInfo.currentRss - rss) >> 20} MB after scrolling through all',
    );
    await tester.pumpWidget(const SizedBox());
  });
}

void _longSession() {
  testWidgets('a long session: writing on 300 pages keeps few pages in memory', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (s, nb) = _lectures(lines: 10);
    addTearDown(s.dispose);
    await tester.pumpWidget(
      AppScope(
        services: s,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: EditorScreen(notebook: nb),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
    final pages = doc.pages;
    int alive() => pages.where((p) => doc.surfaces.models.peek(p.id) != null).length;
    final rss = ProcessInfo.currentRss;
    final watch = Stopwatch()..start();
    for (var i = 0; i < 300; i++) {
      doc.goToPage(i);
      await tester.pump();
      final at = tester.getCenter(find.byType(PagedDocumentView));
      final pen = await tester.startGesture(at, kind: PointerDeviceKind.stylus);
      for (var k = 0; k < 6; k++) {
        await pen.moveBy(const Offset(8, 2));
      }
      await pen.up();
      await tester.pump();
    }
    final perPage = watch.elapsedMilliseconds ~/ 300;
    final models = alive();
    final held = doc.surfaces.all.length;
    // Pages undo can reach, and those the view keeps near the screen.
    expect(models, lessThanOrEqualTo(PageModels.maxPages + 1));
    expect(held, lessThanOrEqualTo(10));
    final grown = (ProcessInfo.currentRss - rss) >> 20;
    // Every stroke is still undoable, as far back as the history reaches.
    final undo = doc.surfaces.models;
    var steps = 0;
    while (undo.canUndo && steps < 1000) {
      undo.undo();
      steps++;
    }
    report(
      'long session, 300 pages written on: $models page models alive ($held with render '
      'caches), RSS +$grown MB, '
      '$steps undo steps, ${perPage}ms a page',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

Future<void> _closeAndReport(
  WidgetTester tester,
  DocumentController doc,
  AppServices s,
  ({int? strokes, int firstFrame, int opened, int jump, int jumpSettled, List<int> frames}) r,
) async {
  report(
    '500-page notebook (${r.strokes} strokes): first frame ${r.firstFrame}ms, settled '
    '${r.opened}ms; go to page 500 ${r.jump}ms (settled ${r.jumpSettled}ms); scroll frames '
    'median ${r.frames[r.frames.length ~/ 2]}ms, max ${r.frames.last}ms',
  );
  expect(find.byType(PageOverview), findsNothing);
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}
