import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/export/export_report.dart';
import 'package:len/features/documents/export/export_sheet.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';
import 'package:len/features/documents/export/notebooks_export.dart';
import 'package:len/platform/file_export.dart';

import 'library_ui_test.dart' show addNotebook, openMenuOf, pumpSeeded;

/// Records the pages of each PDF instead of rendering.
class _FakeExporter extends NotebookExporter {
  _FakeExporter(super.services);

  final pdfCalls = <(String?, int)>[];

  @override
  Future<Uint8List> pdf(
    List<NotebookPage> pages, {
    String? title,
    ExportProgress? onProgress,
    bool backgrounds = true,
    void Function(int index)? onRasterized,
    ExportReport? report,
  }) async {
    pdfCalls.add((title, pages.length));
    return Uint8List.fromList([1]);
  }
}

/// Adds [count] pages after the first one a notebook starts with.
void addPages(AppServices s, Notebook n, int count) {
  for (var i = 0; i < count; i++) {
    s.pages.addPage(n.id, template: const PageTemplate(paper: Paper(PaperStyle.wideRuled)));
  }
}

/// Closes the export sheet without exporting.
Future<void> close(WidgetTester tester) async {
  Navigator.of(tester.element(find.byKey(const ValueKey('export-button')))).pop();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('several notebooks export one PDF each, names kept apart (R7-8)', (tester) async {
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    final a = addNotebook(services, 'Lab');
    final b = addNotebook(services, 'Lab');
    final c = addNotebook(services, 'Physics');
    addPages(services, a, 2);
    addPages(services, b, 1);
    addPages(services, c, 3);
    final exporter = _FakeExporter(services);
    final saved = <String>[];
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => exportNotebooks(
                  context,
                  [a, b, c],
                  exporter: exporter,
                  save: (files, {required mime, toDevice = false}) async {
                    saved.addAll([for (final f in files) f.name]);
                    return ExportedFiles(ExportedTo.shared, count: files.length);
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
    expect(find.text('3 notebooks'), findsOneWidget);
    expect(find.text('Pages'), findsNothing); // Whole notebooks: no range.
    expect(find.text('9 pages, PDF'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('export-button')));
    await tester.pumpAndSettle();
    expect(exporter.pdfCalls, [('Lab', 3), ('Lab', 2), ('Physics', 4)]);
    expect(saved, ['Lab.pdf', 'Lab (2).pdf', 'Physics.pdf']);
    expect(find.text('Shared 3 files'), findsOneWidget);
  });

  testWidgets('the notebook menu and the selection bar export (R7-8)', (tester) async {
    await pumpSeeded(tester, (s) {
      addPages(s, addNotebook(s, 'Algebra'), 3);
      addPages(s, addNotebook(s, 'Biology'), 1);
    });
    await openMenuOf(tester, 'Algebra');
    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();
    // The editor's sheet, with all pages and their range.
    expect(find.text('Export'), findsWidgets);
    expect(find.text('Pages'), findsOneWidget);
    expect(find.text('4 pages, PDF'), findsOneWidget);
    await close(tester);

    await openMenuOf(tester, 'Algebra');
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Biology'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Export…'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(ExportSheet), matching: find.text('2 notebooks')),
      findsOne,
    );
    expect(find.text('6 pages, PDF'), findsOneWidget);
    await close(tester);
    expect(find.text('2 selected'), findsNothing); // Done after exporting.
    expect(tester.takeException(), isNull);
  });
}
