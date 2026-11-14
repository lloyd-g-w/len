import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/search/editor/search_highlight_painter.dart';
import 'package:len/ui/app_theme.dart';

import 'search_ui_test.dart' show textBox, typeSearch;

/// Opens a notebook on [paper] in [mode] and searches its text box.
Future<SearchHighlightPainter> highlightsOn(
  WidgetTester tester,
  PaperColor paper,
  ThemeMode mode,
) async {
  final services = AppServices.create(AppDatabase.inMemory());
  addTearDown(services.dispose);
  final notebook = services.notebooks.create(
    title: 'Notes',
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0,
    paperColor: paper,
  );
  final page = services.pages.pagesOf(notebook.id).single;
  services.elements.save([textBox('t', page.id, 'Quarks and gluons', const Offset(90, 300))]);
  tester.view
    ..physicalSize = const Size(900, 1200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        home: EditorScreen(notebook: notebook),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
  await typeSearch(tester, 'quark');
  final paint = tester.widget<CustomPaint>(
    find.byWidgetPredicate((w) => w is CustomPaint && w.painter is SearchHighlightPainter),
  );
  return paint.painter! as SearchHighlightPainter;
}

void main() {
  testWidgets('marks on a light page in the dark theme are the light ones', (tester) async {
    // Marker yellow and the light ring, as in the light theme (no amber on
    // white paper).
    final painter = await highlightsOn(tester, PaperColor.white, ThemeMode.dark);
    expect(painter.matchColor, Palette.searchMatch(Brightness.light));
    expect(painter.currentColor, Tones.light.accent);
  });

  testWidgets('marks on dark paper in the light theme are the dark ones', (tester) async {
    final painter = await highlightsOn(tester, PaperColor.dark, ThemeMode.light);
    expect(painter.matchColor, Palette.searchMatch(Brightness.dark));
    expect(painter.currentColor, Tones.dark.accent);
  });
}
