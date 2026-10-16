import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/export/export_flow.dart';
import 'package:len/features/documents/export/export_report.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';
import 'package:len/platform/file_export.dart';

/// Records what it was asked to export instead of rendering.
class _FakeExporter extends NotebookExporter {
  _FakeExporter(super.services);

  final pdfCalls = <List<NotebookPage>>[];

  /// When set, [pdf] reports progress page by page, waiting for it each time.
  Completer<void>? gate;

  /// When set, [pdf] fails with it.
  Object? error;

  /// Images [pdf] (and each [png]) reports as left out.
  int missingImages = 0;
  final pngCalls = <(NotebookPage, double, bool)>[];

  @override
  Future<Uint8List> pdf(
    List<NotebookPage> pages, {
    String? title,
    ExportProgress? onProgress,
    bool backgrounds = true,
    void Function(int index)? onRasterized,
    ExportReport? report,
  }) async {
    pdfCalls.add(pages);
    if (error case final e?) throw e;
    report?.missingImages += missingImages;
    for (var i = 0; gate != null && i < pages.length; i++) {
      onProgress?.call(ExportStage.writing, i, pages.length);
      await gate!.future;
      gate = Completer();
    }
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<Uint8List> png(
    NotebookPage page, {
    double scale = 2,
    bool backgrounds = true,
    ExportReport? report,
  }) async {
    pngCalls.add((page, scale, backgrounds));
    report?.missingImages += missingImages;
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
  late List<bool> toDevices;
  late List<String?> subjects;

  setUp(() {
    services = AppServices.create(AppDatabase.inMemory());
    notebook = services.notebooks.create(
      title: 'Lab',
      kind: NotebookKind.paged,
      paper: PaperStyle.gridLarge,
      coverColor: 0xFF3B5BDB,
      paperColor: PaperColor.presets.last,
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
    toDevices = [];
    subjects = [];
  });
  tearDown(() => services.dispose());

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    List<int>? initialPages,
  }) async {
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
                  initialPages: initialPages,
                  exporter: exporter,
                  save: (files, {required mime, toDevice = false, subject}) async {
                    saved.add(([for (final f in files) f.name], mime));
                    toDevices.add(toDevice);
                    subjects.add(subject);
                    return ExportedFiles(
                      ExportedTo.file,
                      count: 1,
                      name: files.single.name,
                      path: '/home/me/${files.single.name}',
                    );
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

  testWidgets('a Len file is the whole notebook: no pages or layers to choose', (tester) async {
    await open(tester);
    expect(find.text('Pages'), findsOneWidget);
    await tester.tap(find.text('Len file'));
    await tester.pumpAndSettle();
    expect(find.text('Whole notebook, Len file'), findsOneWidget);
    expect(find.text('Pages'), findsNothing);
    expect(find.text('Include'), findsNothing);
  });

  testWidgets('a page range exports exactly those pages', (tester) async {
    await open(tester);
    expect(find.text('5 pages, PDF'), findsOneWidget); // All pages preselected.
    await tester.tap(find.text('Page range'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('export-range')), '2-9');
    await tester.pump();
    expect(find.text('Pages are 1–5'), findsOneWidget);
    expect(tester.widget<FilledButton>(_exportButton).onPressed, isNull);

    await tester.enterText(find.byKey(const ValueKey('export-range')), '1-2, 4');
    await tester.pump();
    expect(find.text('3 pages, PDF'), findsOneWidget);
    await tester.tap(_exportButton);
    await tester.pumpAndSettle();

    expect(exporter.pdfCalls.single.map((p) => p.id), [pages[0].id, pages[1].id, pages[3].id]);
    expect(exporter.pdfCalls.single.first.paper.style, PaperStyle.gridLarge);
    expect(saved.single.$1, ['Lab p1-2,4.pdf']);
    expect(saved.single.$2, 'application/pdf');
    expect(find.text('Saved “Lab p1-2,4.pdf”'), findsOneWidget);
  });

  testWidgets('pages selected in the overview start as the page range', (tester) async {
    await open(tester, initialPages: [0, 1, 2, 4]);
    expect(find.text('4 pages, PDF'), findsOneWidget);
    expect(find.text('1-3, 5'), findsOneWidget);
    await tester.tap(_exportButton);
    await tester.pumpAndSettle();
    expect(exporter.pdfCalls.single.map((p) => p.id), [
      for (final i in [0, 1, 2, 4]) pages[i].id,
    ]);
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
    expect(find.textContaining('Couldn’t export'), findsNothing);
  });

  testWidgets('PNG of the current page without templates is plain paper', (tester) async {
    await open(tester, size: const Size(390, 844)); // Phone: bottom sheet.
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.text('PNG'));
    await tester.tap(find.text('Current page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Templates'));
    await tester.pumpAndSettle();
    expect(find.text('1 page, PNG at 288 dpi'), findsOneWidget);
    expect(find.text('PDF backgrounds'), findsNothing); // No imported PDF pages.
    await tester.tap(_exportButton);
    await tester.pumpAndSettle();

    final (page, scale, _) = exporter.pngCalls.single;
    expect(page.id, pages[1].id);
    expect(page.paper.style, PaperStyle.blank);
    expect(page.paperColor, PaperColor.white);
    expect(scale, 3);
    expect(saved.single.$1, ['Lab p2.png']);
    // A mail gets the notebook's title as its subject (R22-4).
    expect(subjects.single, 'Lab');
  });

  testWidgets('the next export starts with the last one\'s choices (UX_AUDIT R22-2)', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('PNG'));
    await tester.tap(find.text('Current page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Templates'));
    await tester.pumpAndSettle();
    await tester.tap(_exportButton);
    await tester.pumpAndSettle();

    // Again: PNG, the current page, no templates.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('1 page, PNG at 288 dpi'), findsOneWidget);
    expect(find.text('Plain white paper'), findsOneWidget);
    // A typed range is not kept: the next sheet starts where the caller asks.
    await tester.tap(find.text('Page range'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('export-range')), '3');
    await tester.pumpAndSettle();
    await tester.tap(_exportButton);
    await tester.pumpAndSettle();
    expect(saved.last.$1, ['Lab p3.png']);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('${pages.length} pages, PNG at 288 dpi'), findsOneWidget);
  });

  testWidgets('cancel exports nothing', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(_exportButton, findsNothing);
    expect(exporter.pdfCalls, isEmpty);
    expect(saved, isEmpty);
  });

  testWidgets('what an export leaves out is said at the end (UX_AUDIT P2-29)', (tester) async {
    exporter.missingImages = 2;
    await open(tester);
    await tester.tap(_exportButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('; 2 images couldn’t be included'), findsOneWidget);
  });

  testWidgets('PNG exports say what they left out too', (tester) async {
    exporter.missingImages = 1;
    await open(tester);
    await tester.tap(find.text('PNG'));
    await tester.tap(find.text('Current page'));
    await tester.pumpAndSettle();
    await tester.tap(_exportButton);
    await tester.pumpAndSettle();
    expect(exporter.pngCalls, hasLength(1));
    expect(find.textContaining('; 1 image couldn’t be included'), findsOneWidget);
  });

  testWidgets('a failed export says so in words, the error under Details', (tester) async {
    exporter.error = const FileSystemException('No space left on device', '/tmp/x');
    await open(tester);
    await tester.tap(_exportButton);
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t export “Lab.pdf”'), findsOneWidget);
    expect(find.textContaining('No space left'), findsNothing);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No space left'), findsOneWidget);
  });

  testWidgets('Android: Save to device beside Share (UX_AUDIT P1-24)', (tester) async {
    await open(tester);
    expect(find.text('Share'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-to-device-button')));
    await tester.pumpAndSettle();
    expect(toDevices, [true]);
  });

  testWidgets('desktop: one Export button, then where the file went', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('save-to-device-button')), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(_exportButton);
    await tester.pumpAndSettle();
    expect(toDevices, [false]);
    expect(find.text('Saved “Lab.pdf”'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Show in folder'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  test('the report reads as one line', () {
    expect(ExportReport().summary, isNull);
    final report = ExportReport()
      ..missingBackgrounds = 1
      ..missingImages = 3
      ..rasterizedPages = 2;
    expect(
      report.summary,
      '1 PDF page not on this device was left out; 3 images couldn’t be included; '
      '2 PDF pages were included as a picture',
    );
  });
}
