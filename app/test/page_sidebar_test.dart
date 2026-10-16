import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/overview/page_commands.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/sidebar/page_sidebar.dart';
import 'package:len/features/editor/sidebar/sidebar_tile.dart';
import 'package:len/ui/app_theme.dart';

import 'support/zoom_fixtures.dart';

/// A paged notebook of [pages] blank pages, its page sidebar [open].
({AppServices services, Notebook notebook}) _notebook({int pages = 6, bool open = true}) {
  final s = AppServices.create(AppDatabase.inMemory());
  final nb = s.notebooks.create(
    title: 'Lectures',
    kind: NotebookKind.paged,
    paper: PaperStyle.collegeRuled,
    coverColor: 0,
    firstPage: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)),
  );
  for (var i = 1; i < pages; i++) {
    s.pages.addPage(nb.id, template: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)));
  }
  s.settings.setPageSidebar(nb.id, open);
  return (services: s, notebook: nb);
}

Future<AppServices> _pump(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  int pages = 6,
  bool open = true,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final (:services, :notebook) = _notebook(pages: pages, open: open);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: EditorScreen(notebook: notebook),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return services;
}

Future<void> _close(WidgetTester tester, AppServices services) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
  services.dispose();
}

Finder _tile(int number) =>
    find.byWidgetPredicate((w) => w is SidebarTile && w.index == number - 1);

/// Page [number]'s tile says it is the page on screen.
bool _isCurrent(WidgetTester tester, int number) =>
    tester.getSemantics(_tile(number)).label.contains('current page');

void main() {
  testWidgets('beside the page on a wide pane: tap to go, the page on screen marked', (
    tester,
  ) async {
    final s = await _pump(tester);
    expect(find.byType(PageSidebar), findsOneWidget);
    expect(find.text('6 pages'), findsOneWidget);
    final sidebar = tester.getRect(find.byType(PageSidebar));
    expect(sidebar.left, 0);
    expect(sidebar.width, SidebarMetrics.width);
    // The page lies beside it, not under it.
    final canvas = tester.getRect(find.byType(EditorCanvas));
    expect(canvas.left, greaterThanOrEqualTo(sidebar.right - 0.5));

    final doc = zoomSession(tester).doc!;
    final semantics = tester.ensureSemantics();
    expect(_isCurrent(tester, 1), isTrue);
    await tester.tap(_tile(4));
    await tester.pumpAndSettle();
    expect(doc.currentPage, 3);
    expect(_isCurrent(tester, 4), isTrue);
    expect(_isCurrent(tester, 1), isFalse);
    semantics.dispose();
    await _close(tester, s);
  });
}
