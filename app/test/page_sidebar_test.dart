import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/overview/page_commands.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/sidebar/page_sidebar.dart';
import 'package:len/features/editor/sidebar/sidebar_tile.dart';
import 'package:len/features/editor/tabs/editor_workspace.dart';
import 'package:len/ui/app_theme.dart';

import 'document_editor_test.dart' show drawAt;
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

  testWidgets(
    'never on a narrow pane, hidden in focus mode; F4 and its ✕ remembered per notebook',
    (tester) async {
      // A tablet held upright: no room beside the page.
      var s = await _pump(tester, size: const Size(800, 1280));
      expect(find.byType(PageSidebar), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.f4);
      await tester.pump();
      expect(find.text('No room for pages beside the page here'), findsOneWidget);
      await _close(tester, s);

      s = await _pump(tester);
      final id = zoomSession(tester).notebook.id;
      expect(find.byType(PageSidebar), findsOneWidget);
      // Focus mode leaves nothing but the page; leaving it brings it back.
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      expect(find.byType(PageSidebar), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.f4); // Not in focus mode.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PageSidebar), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.f4);
      await tester.pumpAndSettle();
      expect(find.byType(PageSidebar), findsNothing);
      expect(s.settings.pageSidebar(id), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.f4);
      await tester.pumpAndSettle();
      expect(find.byType(PageSidebar), findsOneWidget);
      expect(s.settings.pageSidebar(id), isTrue);
      await tester.tap(find.byTooltip(Targets.touchFirst ? 'Hide pages' : 'Hide pages (F4)'));
      await tester.pumpAndSettle();
      expect(find.byType(PageSidebar), findsNothing);
      expect(s.settings.pageSidebar(id), isFalse);
      await _close(tester, s);
    },
  );

  testWidgets('the overview offers it: Show beside the page', (tester) async {
    final s = await _pump(tester, open: false);
    expect(find.byType(PageSidebar), findsNothing);
    await tester.tap(find.byTooltip('All pages'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show beside the page'));
    await tester.pumpAndSettle();
    expect(find.text('Pages'), findsNothing, reason: 'the overview closed');
    expect(find.byType(PageSidebar), findsOneWidget);
    expect(s.settings.pageSidebar(zoomSession(tester).notebook.id), isTrue);
    // Shown, the overview no longer offers it.
    await tester.tap(find.byTooltip('All pages'));
    await tester.pumpAndSettle();
    expect(find.text('Show beside the page'), findsNothing);
    await _close(tester, s);
  });

  testWidgets('the page menu on a right-click or a hold; Add page at the end', (tester) async {
    final s = await _pump(tester, pages: 3);
    final doc = zoomSession(tester).doc!;
    await tester.tap(_tile(2), buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    for (final c in PageCommand.menu) {
      expect(find.text(c.labelFor()), findsOneWidget, reason: c.name);
    }
    await tester.tap(find.text('Bookmark page'));
    await tester.pumpAndSettle();
    expect(doc.pages[1].bookmarked, isTrue);
    expect(tester.getSemantics(_tile(2)).label, contains('bookmarked'));

    // Held until it lifts and let go in place: the menu, for that page.
    final hold = await tester.startGesture(tester.getCenter(_tile(3)));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await hold.up();
    await tester.pumpAndSettle();
    expect(find.text('Bookmark page'), findsOneWidget);
    await tester.tap(find.text('Delete page'));
    await tester.pumpAndSettle();
    expect(doc.pages.length, 2);
    expect(find.text('2 pages'), findsOneWidget);

    await tester.tap(find.text('Add page'));
    await tester.pumpAndSettle();
    expect(doc.pages.length, 3);
    expect(doc.currentPage, 2, reason: 'the new page is shown');
    await _close(tester, s);
  });

  testWidgets('drag to reorder and Ctrl+arrows: one undo step each', (tester) async {
    final s = await _pump(tester, pages: 4);
    final doc = zoomSession(tester).doc!;
    final ids = [for (final p in doc.pages) p.id];
    final drag = await tester.startGesture(tester.getCenter(_tile(1)));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    final to = tester.getCenter(_tile(3)) + const Offset(0, 30);
    for (var i = 1; i <= 10; i++) {
      await drag.moveTo(Offset.lerp(tester.getCenter(_tile(1)), to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect([for (final p in doc.pages) p.id], [ids[1], ids[2], ids[0], ids[3]]);
    expect(find.text('Bookmark page'), findsNothing, reason: 'a drag is no hold');
    await _undo(tester);
    expect([for (final p in doc.pages) p.id], ids);

    // From the keyboard: Ctrl+↓ moves the focused page a place on.
    Focus.of(tester.element(find.text('2'))).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect([for (final p in doc.pages) p.id], [ids[0], ids[2], ids[1], ids[3]]);
    await _undo(tester);
    expect([for (final p in doc.pages) p.id], ids);
    await _close(tester, s);
  });

  testWidgets('keyboard: ↑ ↓ between pages, Enter goes, ← → stay in the column', (tester) async {
    final s = await _pump(tester, pages: 5);
    final doc = zoomSession(tester).doc!;
    Focus.of(tester.element(find.text('1'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // No page turn.
    await tester.pumpAndSettle();
    expect(doc.currentPage, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(doc.currentPage, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(doc.currentPage, 4);
    await _close(tester, s);
  });

  testWidgets('the page on screen is kept in view as the notebook scrolls', (tester) async {
    final s = await _pump(tester, pages: 40);
    final doc = zoomSession(tester).doc!;
    final list = find.descendant(of: find.byType(PageSidebar), matching: find.byType(Scrollable));
    final column = tester.getRect(list);
    doc.goToPage(30);
    await tester.pumpAndSettle();
    final tile = tester.getRect(_tile(31));
    expect(column.top <= tile.top && tile.bottom <= column.bottom, isTrue, reason: '$tile');
    // Scrolled back a page at a time, it follows.
    for (var i = 29; i >= 25; i--) {
      doc.goToPage(i);
      await tester.pumpAndSettle();
      final r = tester.getRect(_tile(i + 1));
      expect(column.top <= r.top && r.bottom <= column.bottom, isTrue, reason: 'page ${i + 1}');
    }
    await _close(tester, s);
  });
  testWidgets('thumbnails follow the writing once the pen rests', (tester) async {
    final s = await _pump(tester, pages: 3);
    final page = zoomSession(tester).doc!.pages.first;
    final cache = tester.widget<SidebarTile>(_tile(1)).cache;
    final before = cache.inkOf(page.id);
    expect(before, isNotNull);
    final recorded = cache.recordings;
    await drawAt(tester, tester.getCenter(find.byType(PagedDocumentView)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(cache.recordings, recorded, reason: 'not while writing');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(cache.recordings, recorded + 1, reason: 'only the page written on');
    expect(identical(cache.inkOf(page.id), before), isFalse);
    await _close(tester, s);
  });

  testWidgets('split view: per pane, only where the pane has room', (tester) async {
    tester.view
      ..physicalSize = const Size(2560, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    Notebook make(String title) {
      final nb = s.notebooks.create(
        title: title,
        kind: NotebookKind.paged,
        paper: PaperStyle.collegeRuled,
        coverColor: 0,
      );
      s.settings.setPageSidebar(nb.id, true);
      return nb;
    }

    final physics = make('Physics'), chemistry = make('Chemistry');
    s.openNotebooks
      ..open(chemistry)
      ..open(physics)
      ..openSplit(chemistry.id);
    await tester.pumpWidget(
      AppScope(
        services: s,
        child: MaterialApp(theme: AppTheme.light(), home: const EditorWorkspace()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PageSidebar), findsNWidgets(2));
    // Each beside its own pane's page.
    final panes = find.byType(PagedDocumentView);
    for (var i = 0; i < 2; i++) {
      final sidebar = tester.getRect(find.byType(PageSidebar).at(i));
      final pane = tester.getRect(panes.at(i));
      expect(sidebar.right, lessThanOrEqualTo(pane.left + 0.5));
      expect(pane.left - sidebar.right, lessThan(2));
    }
    // A smaller window: panes too narrow for it.
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.byType(PagedDocumentView), findsNWidgets(2));
    expect(find.byType(PageSidebar), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}

Future<void> _undo(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}
