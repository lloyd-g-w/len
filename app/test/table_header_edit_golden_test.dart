import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/text/rich_text_buffer.dart';
import 'package:len/domain/text/table_edits.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/tools/text/table_editor_layer.dart';
import 'package:len/ink/elements/text_layout.dart';

import 'content_golden_test.dart' show loadFonts, text;
import 'search_ui_test.dart' show pumpEditorFor;
import 'table_editor_test.dart' show boxController, typeInCell;

/// While a table running over the page edge is edited, the field shows
/// its header row again at the top of the next page, as the part there
/// draws it at rest, and live: typing in a header cell changes it there
/// too (UX_AUDIT R27-8).
void main() {
  testWidgets('a table over pages being edited repeats its header row live (golden)', (
    tester,
  ) async {
    await loadFonts();
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    final nb = services.notebooks.create(
      title: 'Notes',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0xFF3B5BDB,
    );
    services.pages.addPage(nb.id);
    final page = services.pages.pagesOf(nb.id).first;
    final b = RichTextBuffer(const TextData(text: 'Reading list'));
    final t = b.insertTable(12, 10, 2, header: true);
    for (var k = 0; k < t.cells; k++) {
      final s = switch (k) {
        0 => 'Book',
        1 => 'Chapter',
        _ when k.isEven => 'Book ${k ~/ 2}',
        _ => 'Chapter ${k ~/ 2}',
      };
      b.setCell(t.line + k, s, List.filled(s.length, SpanStyle.plain));
    }
    final data = b.toData(TextData(text: '', font: TextFont.inter, fontSize: 22));
    final box = text(page.id, Offset(90, page.height - 260), data, width: 420);
    services.elements.save([box]);
    await pumpEditorFor(tester, services, nb, size: const Size(900, 1200));

    // Open the chain with the Text tool: one field over both pages.
    final doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();
    await tester.tapAt(doc.pageViewport.toScreen(box.rect.topLeft + const Offset(40, 10)));
    await tester.pumpAndSettle();
    final field = boxController(tester);
    expect(field.breaks, isNotEmpty, reason: 'the table runs over the page edge');

    // The header is shown at the top of the next page's part.
    List<({Rect rect, int table})> headers() {
      final plan = field.plan;
      final layout = TextBoxLayout.planned(field.data, field.wrapWidth, plan);
      addTearDown(layout.dispose);
      return TableEditorLayer.repeatedHeaders(field.data, plan.tables, layout.rows, field.breaks);
    }

    final shown = headers();
    expect(shown, hasLength(1));
    final band = shown.single.rect;
    final table = field.plan.tables.single;
    expect(band.height, closeTo(table.rowHeights.first, 0.01));
    expect(band.top, greaterThan(field.plan.tables.single.rowHeights.first * 3));

    // Typing in a body cell lays out only that cell: the repeated header
    // is painted from the header row's own layouts.
    final body = t.lineOf(1, 1);
    field.enterCell(body, atEnd: true);
    await tester.pumpAndSettle();
    final before = TableLayout.debugCellLayouts;
    await typeInCell(tester, 'Chapter 1, part one');
    await tester.pumpAndSettle();
    expect(TableLayout.debugCellLayouts - before, lessThanOrEqualTo(2));

    // Typing in a header cell changes the repeated row at once.
    field.enterCell(t.lineOf(0, 1), atEnd: true);
    await tester.pumpAndSettle();
    await typeInCell(tester, 'Chapters read');
    await tester.pumpAndSettle();
    expect(field.plan.tables.single.cells[1].data.text, 'Chapters read');
    expect(headers(), hasLength(1));
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/table_header_edit.png'),
    );
  });
}
