import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/document/document_controller.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/outline/outline_panel.dart';

import 'document_editor_test.dart' show closeEditor, pumpEditor;

DocumentController _doc(WidgetTester tester) =>
    tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;

Future<void> _menu(WidgetTester tester, String item, {bool page = true}) async {
  await tester.tap(find.byTooltip('More options'));
  await tester.pumpAndSettle();
  if (page) {
    await tester.tap(find.text('Page'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('add pages to the outline, nest, jump, rename and delete', (tester) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(1280, 900));
    final pages = s.pages.pagesOf(nb.id);

    // Page 1 → "Intro" at the top level.
    await _menu(tester, 'Add page to outline…');
    await tester.enterText(find.byKey(const ValueKey('outline-title-field')), 'Intro');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(s.outline.entriesOf(nb.id).single.pageId, pages[0].id);

    // Page 3 → "Details", nested under Intro from the panel.
    _doc(tester).scrollToPage(2);
    await tester.pumpAndSettle();
    await _menu(tester, 'Outline', page: false);
    expect(find.byType(OutlinePanel), findsOneWidget);
    expect(find.text('Intro'), findsOneWidget);
    await tester.tap(find.text('Add page 3'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('outline-title-field')), 'Details');
    await tester.tap(find.byKey(const ValueKey('outline-parent-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Intro').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    final details = s.outline.entriesOf(nb.id).firstWhere((e) => e.title == 'Details');
    expect(details.parentId, isNotNull);
    expect(details.pageId, pages[2].id);
    await expectLater(find.byType(OutlinePanel), matchesGoldenFile('goldens/outline_panel.png'));

    // Collapse hides the child; tapping Intro jumps to page 1.
    await tester.tap(find.byTooltip('Collapse'));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsNothing);
    await tester.tap(find.byTooltip('Expand'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Intro'));
    await tester.pumpAndSettle();
    expect(find.byType(OutlinePanel), findsNothing);
    expect(_doc(tester).currentPage, 0);

    // Rename and delete from an entry's menu; Undo brings it back.
    await _menu(tester, 'Outline', page: false);
    await tester.tap(find.byTooltip('Entry options').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move out a level'));
    await tester.pumpAndSettle();
    expect(s.outline.get(details.id)!.parentId, isNull);
    await tester.tap(find.byTooltip('Entry options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('outline-title-field')), 'Start');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget);
    await tester.tap(find.byTooltip('Entry options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(s.outline.entriesOf(nb.id).single.title, 'Details');
    expect(find.text('Start'), findsNothing);
    await closeEditor(tester);
  });

  testWidgets('the overview\'s Outline filter shows the outline in place of the grid', (
    tester,
  ) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(1280, 900));
    await _menu(tester, 'Add page to outline…');
    await tester.enterText(find.byKey(const ValueKey('outline-title-field')), 'Intro');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    _doc(tester).scrollToPage(2);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('All pages'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-tile-0')), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    await tester.tap(find.text('Outline'));
    await tester.pumpAndSettle();
    expect(find.byType(OutlinePanel), findsOneWidget);
    expect(find.byKey(const ValueKey('page-tile-0')), findsNothing);
    expect(find.text('Select'), findsNothing, reason: 'nothing to select in the outline');
    // Picking an entry closes the overview on its page.
    await tester.tap(find.text('Intro'));
    await tester.pumpAndSettle();
    expect(find.byType(OutlinePanel), findsNothing);
    expect(_doc(tester).currentPage, 0);
    expect(s.outline.entriesOf(nb.id), hasLength(1));
    await closeEditor(tester);
  });
}
