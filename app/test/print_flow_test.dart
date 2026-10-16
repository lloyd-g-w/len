import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/export/export_options.dart';
import 'package:len/features/documents/export/export_report.dart';
import 'package:len/features/documents/export/export_sheet.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';
import 'package:len/features/documents/export/print_flow.dart';
import 'package:len/features/documents/progress_dialog.dart';
import 'package:len/platform/print_document.dart';

import 'document_editor_test.dart' show pumpEditor;
import 'library_export_test.dart' show addPages;
import 'library_ui_test.dart' show addNotebook, openMenuOf, pumpSeeded;

/// Records what it was asked to render instead of rendering.
class _FakeExporter extends NotebookExporter {
  _FakeExporter(super.services);

  final pdfCalls = <(List<NotebookPage>, bool)>[];

  /// When set, [pdf] waits for it after reporting its first page.
  Completer<void>? gate;
  int missingImages = 0;

  @override
  Future<Uint8List> pdf(
    List<NotebookPage> pages, {
    String? title,
    ExportProgress? onProgress,
    bool backgrounds = true,
    void Function(int index)? onRasterized,
    ExportReport? report,
  }) async {
    pdfCalls.add((pages, backgrounds));
    report?.missingImages += missingImages;
    if (gate case final gate?) {
      onProgress?.call(ExportStage.writing, 0, pages.length);
      await gate.future;
    }
    return Uint8List.fromList([1, 2, 3]);
  }
}

/// A printer that records what it was given.
class _FakePrinter {
  PrintHandoff handoff = PrintHandoff.dialog;
  Object? error;
  final printed = <(Uint8List, String, int)>[];

  Future<PrintHandoff> call(Uint8List bytes, {required String name, required int pages}) async {
    printed.add((bytes, name, pages));
    if (error case final e?) throw e;
    return handoff;
  }
}

final _printButton = find.byKey(const ValueKey('print-button'));

/// The sheet's summary, saying [text].
Finder _summary(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.key == const ValueKey('export-summary') && w.data == text,
);

void main() {
  late AppServices services;
  late Notebook notebook;
  late List<NotebookPage> pages;
  late _FakeExporter exporter;
  late _FakePrinter printer;

  setUp(() {
    ExportMemory.reset();
    services = AppServices.create(AppDatabase.inMemory());
    notebook = services.notebooks.create(
      title: 'Lab',
      kind: NotebookKind.paged,
      paper: PaperStyle.gridLarge,
      coverColor: 0,
    );
    addPages(services, notebook, 3);
    pages = services.pages.pagesOf(notebook.id);
    exporter = _FakeExporter(services);
    printer = _FakePrinter();
  });
  tearDown(() => services.dispose());

  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => printFlow(
                  context,
                  notebook: notebook,
                  pages: pages,
                  currentPage: 1,
                  exporter: exporter,
                  printer: printer.call,
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

  testWidgets('Print is the export sheet as a PDF, with a Print button (R22-8)', (tester) async {
    await open(tester);
    expect(find.text('Print'), findsWidgets);
    expect(find.text('PNG'), findsNothing, reason: 'no format to choose');
    expect(find.text('Pages'), findsOneWidget);
    expect(find.text('Templates'), findsOneWidget);
    expect(find.byKey(const ValueKey('export-button')), findsNothing);
    expect(_summary('4 pages'), findsOneWidget);
    await tester.tap(_printButton);
    await tester.pumpAndSettle();
    final (bytes, name, count) = printer.printed.single;
    expect(bytes, [1, 2, 3]);
    expect(name, 'Lab.pdf');
    expect(count, 4);
    expect(exporter.pdfCalls.single.$1, hasLength(4));
    // The system's print dialog speaks for itself.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the chosen pages and layers are printed', (tester) async {
    await open(tester);
    await tester.tap(find.text('Current page'));
    await tester.tap(find.text('Templates'));
    await tester.pumpAndSettle();
    expect(_summary('1 page'), findsOneWidget);
    await tester.tap(_printButton);
    await tester.pumpAndSettle();
    expect(printer.printed.single.$2, 'Lab p2.pdf');
    expect(printer.printed.single.$3, 1);
    final printedPage = exporter.pdfCalls.single.$1.single;
    expect(printedPage.id, pages[1].id);
    expect(printedPage.paper, Paper.blank, reason: 'without templates: plain paper');
  });

  testWidgets('printing leaves the export\'s format alone', (tester) async {
    ExportMemory.format = ExportFormat.png;
    await open(tester);
    await tester.tap(_printButton);
    await tester.pumpAndSettle();
    expect(ExportMemory.format, ExportFormat.png);
  });

  testWidgets('a print can be cancelled while it renders: nothing is printed', (tester) async {
    exporter.gate = Completer();
    await open(tester);
    await tester.tap(_printButton);
    await tester.pump();
    expect(find.text('Preparing to print'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(ProgressDialog), matching: find.text('Cancel')),
    );
    await tester.pump();
    exporter.gate!.complete();
    await tester.pumpAndSettle();
    expect(printer.printed, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a PDF opened in a viewer says where to print it', (tester) async {
    printer.handoff = PrintHandoff.viewer;
    await open(tester);
    await tester.tap(_printButton);
    await tester.pumpAndSettle();
    expect(find.text('Opened “Lab.pdf” in your PDF viewer to print'), findsOneWidget);
  });

  testWidgets('what a print leaves out is said even after a print dialog', (tester) async {
    exporter.missingImages = 2;
    await open(tester);
    await tester.tap(_printButton);
    await tester.pumpAndSettle();
    expect(find.text('Printing “Lab.pdf”; 2 images couldn’t be included'), findsOneWidget);
  });

  testWidgets('a failed print says so in words, the error under Details', (tester) async {
    printer.error = PlatformException(code: 'print_failed', message: 'no activity');
    await open(tester);
    await tester.tap(_printButton);
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t print “Lab.pdf”'), findsOneWidget);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no activity'), findsOneWidget);
  });

  testWidgets('Linux: the sheet says the PDF opens in the viewer', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await open(tester);
      expect(find.text('Opens in your PDF viewer to print from there'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the library\'s notebook menu prints', (tester) async {
    await pumpSeeded(tester, (s) => addPages(s, addNotebook(s, 'Algebra'), 2));
    await openMenuOf(tester, 'Algebra');
    await tester.tap(find.text('Print…'));
    await tester.pumpAndSettle();
    expect(find.byType(ExportSheet), findsOneWidget);
    expect(_summary('3 pages'), findsOneWidget);
    expect(_printButton, findsOneWidget);
    Navigator.of(tester.element(_printButton)).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('the editor prints from ⋯ and with Ctrl+P', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Print…'));
    await tester.pumpAndSettle();
    expect(_printButton, findsOneWidget);
    expect(_summary('3 pages'), findsOneWidget);
    Navigator.of(tester.element(_printButton)).pop();
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(_printButton, findsOneWidget);
    Navigator.of(tester.element(_printButton)).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
