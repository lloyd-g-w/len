import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/export/export_flow.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';

/// Records what it was asked to export instead of rendering.
class _FakeExporter extends NotebookExporter {
  _FakeExporter(super.services);

  final pdfCalls = <List<NotebookPage>>[];

  /// When set, [pdf] reports progress page by page, waiting for it each time.
  Completer<void>? gate;
  final pngCalls = <(NotebookPage, double, bool)>[];

  @override
  Future<Uint8List> pdf(
    List<NotebookPage> pages, {
    String? title,
    ExportProgress? onProgress,
    bool backgrounds = true,
    void Function(int index)? onRasterized,
  }) async {
    pdfCalls.add(pages);
    for (var i = 0; gate != null && i < pages.length; i++) {
      onProgress?.call(ExportStage.writing, i, pages.length);
      await gate!.future;
      gate = Completer();
    }
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<Uint8List> png(NotebookPage page, {double scale = 2, bool backgrounds = true}) async {
    pngCalls.add((page, scale, backgrounds));
    return Uint8List.fromList([4]);
  }
}

final _exportButton = find.byKey(const ValueKey('export-button'));

void main() {
  late AppServices services;
  late Notebook notebook;
  late List<NotebookPage> pages;
  late _FakeExporter exporter;
  late List<(List<String>, String)> saved;

  setUp(() {
    services = AppServices.create(AppDatabase.inMemory());
    notebook = services.notebooks.create(
      title: 'Lab',
      kind: NotebookKind.paged,
      paper: PaperStyle.gridLarge,
      coverColor: 0xFF3B5BDB,
      paperColor: PaperColor.values.last,
    );
    for (var i = 0; i < 4; i++) {
      services.pages.addPage(
        notebook.id,
        template: const PageTemplate(paper: Paper(PaperStyle.wideRuled)),
      );
    }
    pages = services.pages.pagesOf(notebook.id);
    exporter = _FakeExporter(services);
    saved = [];
  });
  tearDown(() => services.dispose());

  Future<void> open(WidgetTester tester, {Size size = const Size(1280, 800)}) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => exportFlow(
                  context,
                  notebook: notebook,
                  pages: pages,
                  currentPage: 1,
                  exporter: exporter,
                  save: (files, {required mime}) async {
                    saved.add(([for (final f in files) f.name], mime));
                    return 'somewhere';
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a page range exports exactly those pages', (tester) async {
    await open(tester);
    expect(find.text('5 pages · PDF'), findsOneWidget); // All pages preselected.
    await tester.tap(find.text('Page range'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('export-range')), '2-9');
    await tester.pump();
    expect(find.text('Pages are 1–5'), findsOneWidget);
    expect(tester.widget<FilledButton>(_exportButton).onPressed, isNull);

    await tester.enterText(find.byKey(const ValueKey('export-range')), '1-2, 4');
    await tester.pump();
    expect(find.text('3 pages · PDF'), findsOneWidget);
    await tester.tap(_exportButton);
    await tester.pumpAndSettle();

    expect(exporter.pdfCalls.single.map((p) => p.id), [pages[0].id, pages[1].id, pages[3].id]);
    expect(exporter.pdfCalls.single.first.paper.style, PaperStyle.gridLarge);
    expect(saved.single.$1, ['Lab p1-2,4.pdf']);
    expect(saved.single.$2, 'application/pdf');
    expect(find.text('Saved somewhere'), findsOneWidget);
  });

  testWidgets('an export can be cancelled: nothing is saved', (tester) async {
    exporter.gate = Completer();
    await open(tester);
    await tester.tap(_exportButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Page 1 of 5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('progress-cancel')));
    await tester.pump();
    expect(find.text('Cancelling…'), findsOneWidget);
    exporter.gate!.complete(); // The exporter reports the next page → stops.
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(saved, isEmpty);
    expect(find.textContaining('Export failed'), findsNothing);
  });

  testWidgets('PNG of the current page without templates is plain paper', (tester) async {
    await open(tester, size: const Size(390, 844)); // Phone: bottom sheet.
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.text('PNG'));
    await tester.tap(find.text('Current page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page templates'));
    await tester.scrollUntilVisible(find.text('High 4×'), 100);
    await tester.tap(find.text('High 4×'));
    await tester.pumpAndSettle();
    expect(find.text('1 page · PNG · 384 dpi'), findsOneWidget);
    expect(find.text('PDF backgrounds'), findsNothing); // No imported PDF pages.
    await tester.tap(_exportButton);
    await tester.pumpAndSettle();

    final (page, scale, _) = exporter.pngCalls.single;
    expect(page.id, pages[1].id);
    expect(page.paper.style, PaperStyle.blank);
    expect(page.paperColor, PaperColor.white);
    expect(scale, 4);
    expect(saved.single.$1, ['Lab p2.png']);
  });

  testWidgets('cancel exports nothing', (tester) async {
    await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_exportButton, findsNothing);
    expect(exporter.pdfCalls, isEmpty);
    expect(saved, isEmpty);
  });
}
