import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/document/paged_document_view.dart';

import 'content_golden_test.dart' show loadFonts, text;
import 'search_ui_test.dart' show pumpEditorFor;

/// Notes with a heading and a numbered list whose items wrap.
final TextData notes = TextData.rich(
  text: [
    'Lecture notes',
    'Typed notes reach the bottom of the page and go on at the top of the next one',
    'Each page keeps its own part, so it draws, searches and exports alone',
    'A numbered list counts on over the page edge',
    'An item cut by the page continues without a second number',
  ].join('\n'),
  paras: [
    const ParaStyle(heading: 2),
    for (var i = 0; i < 4; i++) const ParaStyle(list: ListKind.number),
  ],
  font: TextFont.lora,
  fontSize: 22,
);

void main() {
  testWidgets('text flow: a box running over the page edge, edited and stored', (tester) async {
    await loadFonts();
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    final nb = services.notebooks.create(
      title: 'Notes',
      kind: NotebookKind.paged,
      paper: PaperStyle.collegeRuled,
      coverColor: 0xFF3B5BDB,
    );
    services.pages.addPage(nb.id);
    final page = services.pages.pagesOf(nb.id).first;
    final box = text(page.id, Offset(90, page.height - 240), notes, width: 420);
    services.elements.save([box]);
    await pumpEditorFor(tester, services, nb, size: const Size(900, 1200));

    // Open it with the Text tool and type on: the field shows the text
    // over both pages, the second part at the next page's top margin.
    final doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();
    await tester.tapAt(doc.pageViewport.toScreen(box.rect.topLeft + const Offset(40, 10)));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('text-box-field'));
    final typed = tester.widget<TextField>(field).controller!;
    await tester.enterText(field, '${typed.text} today');
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/text_flow_edit.png'),
    );

    // Finished: one box per page.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(services.elements.allOn(services.pages.pagesOf(nb.id)[1].id), hasLength(1));
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/text_flow_pages.png'),
    );
  });
}
