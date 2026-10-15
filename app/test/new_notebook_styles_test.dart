import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_style.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/library/new_notebook_sheet.dart';
import 'package:len/ui/app_theme.dart';

import 'ui_library_test.dart' show pumpLibrary;

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('New notebook').first);
  await tester.pumpAndSettle();
  expect(find.byType(NewNotebookSheet), findsOneWidget);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder get _summary => find.descendant(
  of: find.byKey(const ValueKey('template-summary')),
  matching: find.byType(Text),
);

String _summaryText(WidgetTester tester) => tester.widget<Text>(_summary.last).data!;

void main() {
  testWidgets('without styles the sheet starts as the last notebook was made', (tester) async {
    final services = await pumpLibrary(tester);
    await _openSheet(tester);
    expect(_summaryText(tester), 'College ruled, white, A4 portrait');
    await _tap(tester, find.text('Small grid'));
    await _tap(tester, find.byKey(const ValueKey('format-a5')));
    await _tap(tester, find.byKey(const ValueKey('cover-2')));
    await _tap(tester, find.text('Create'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(services.preferences.lastNotebookChoice!.paper, PaperStyle.gridSmall);

    await _openSheet(tester);
    expect(_summaryText(tester), 'Small grid, white, A5 portrait');
    expect(find.text(Palette.coverNames[2]), findsOneWidget);
    // A canvas leaves the notebook defaults alone.
    await _tap(tester, find.text('Canvas'));
    await _tap(tester, find.text('Dotted'));
    await _tap(tester, find.text('Create'));
    expect(services.preferences.lastNotebookChoice!.paper, PaperStyle.gridSmall);
  });

  testWidgets('save a style, apply it, make it the default, rename and delete it', (tester) async {
    final services = await pumpLibrary(tester);
    await _openSheet(tester);
    // Before the first style: no Styles row, "Save as style…" under the
    // form (R12-5).
    expect(find.text('Styles'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Save as style…')).dy,
      greaterThan(tester.getTopLeft(find.text('Cover')).dy),
    );
    await _tap(tester, find.text('Dotted'));
    await _tap(tester, find.byKey(const ValueKey('format-a5')));
    await _tap(tester, find.byKey(const ValueKey('cover-1')));
    await _tap(tester, find.text('Save as style…'));
    await tester.enterText(find.byType(TextField).last, 'Lecture');
    await _tap(tester, find.text('Save'));
    final lecture = services.notebookStyles.list().single;
    expect(lecture.name, 'Lecture');
    expect(lecture.choice.paper, PaperStyle.dotted);
    expect(lecture.choice.format, PageFormat.a5);
    expect(lecture.choice.coverColor, Palette.covers[1]);
    expect(find.text('Styles'), findsOneWidget);
    // The form is that style now: nothing new to save.
    expect(find.text('Save as style…'), findsNothing);

    // Another choice; the style fills in everything at once.
    await _tap(tester, find.text('Blank'));
    await _tap(tester, find.byKey(const ValueKey('format-a4')));
    expect(find.text('Save as style…'), findsOneWidget);
    await _tap(tester, find.text('Lecture'));
    expect(_summaryText(tester), 'Dotted, white, A5 portrait');
    expect(find.text(Palette.coverNames[1]), findsOneWidget);

    // Tapping the chosen style again opens its menu.
    await _tap(tester, find.text('Lecture'));
    await _tap(tester, find.text('Default for new notebooks'));
    expect(services.notebookStyles.defaultStyle()!.id, lecture.id);
    expect(find.text('Default'), findsOneWidget);

    await _tap(tester, find.text('Cancel'));
    // The default wins over the last notebook made.
    services.preferences.lastNotebookChoice = const NotebookChoice(coverColor: 0);
    await _openSheet(tester);
    expect(_summaryText(tester), 'Dotted, white, A5 portrait');

    await tester.longPress(find.text('Lecture'));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Rename…'));
    await tester.enterText(find.byType(TextField).last, 'Lectures');
    await _tap(tester, find.text('Rename'));
    expect(find.text('Lectures'), findsOneWidget);
    expect(services.notebookStyles.get(lecture.id)!.name, 'Lectures');

    await tester.longPress(find.text('Lectures'));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Delete…'));
    await _tap(tester, find.text('Delete'));
    expect(services.notebookStyles.list(), isEmpty);
    expect(find.text('Lectures'), findsNothing);
    expect(find.text('Styles'), findsNothing);
    expect(find.text('Save as style…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a default canvas style opens the sheet as a new canvas and creates one', (
    tester,
  ) async {
    final services = await pumpLibrary(tester);
    final style = services.notebookStyles.create(
      name: 'Board',
      choice: NotebookChoice(
        kind: NotebookKind.canvas,
        paper: PaperStyle.gridSmall,
        paperColor: PaperColor.dark,
        coverColor: Palette.covers[3],
      ),
    );
    services.notebookStyles.setDefault(style.id, isDefault: true);
    await _openSheet(tester);
    expect(find.text('New canvas'), findsOneWidget);
    expect(_summaryText(tester), 'Small grid, dark, infinite canvas');
    await _tap(tester, find.text('Create'));
    final notebook = services.notebooks.list().single;
    expect(notebook.kind, NotebookKind.canvas);
    expect(notebook.paper.style, PaperStyle.gridSmall);
    expect(notebook.paperColor, PaperColor.dark);
    expect(notebook.coverColor, Palette.covers[3]);
  });

  testWidgets('a planner style makes planners in its calendar (week start, language)', (
    tester,
  ) async {
    final services = await pumpLibrary(tester);
    const calendar = PlannerCalendar(weekStart: WeekStart.sunday, language: PlannerLanguage.fr);
    final style = services.notebookStyles.create(
      name: 'Agenda',
      choice: NotebookChoice(
        paper: PaperStyle.weeklyPlanner,
        calendar: calendar,
        coverColor: Palette.covers[2],
      ),
    );
    services.notebookStyles.setDefault(style.id, isDefault: true);
    await _openSheet(tester);
    // The form is that style: nothing new to save.
    expect(find.text('Save as style…'), findsNothing);
    await _tap(tester, find.text('Create'));
    final notebook = services.notebooks.list().single;
    final pages = services.pages.pagesOf(notebook.id);
    expect(pages, isNotEmpty);
    for (final page in pages) {
      expect(page.paper.calendar, calendar);
    }
  });
}
