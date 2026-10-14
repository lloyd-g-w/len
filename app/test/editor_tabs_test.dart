import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/link_target.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/chrome/editor_chrome.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/tabs/editor_workspace.dart';
import 'package:len/features/editor/tabs/notebook_tab_strip.dart';
import 'package:len/features/editor/tabs/open_notebooks.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/ui/app_theme.dart';

import 'support/page_actions.dart';

Notebook notebook(String id, {NotebookKind kind = NotebookKind.paged}) => Notebook(
  id: id,
  title: 'Notebook $id',
  kind: kind,
  paper: Paper.blank,
  coverColor: 0,
  createdAt: 0,
  updatedAt: 0,
);

/// Taps the cover above a notebook's title in the library.
Future<void> openCard(WidgetTester tester, String title) async {
  await tester.tapAt(tester.getCenter(find.text(title)) - const Offset(0, 80));
  await tester.pumpAndSettle();
}

void main() {
  group('OpenNotebooks', () {
    test('opens after the active tab, activates, and re-opening switches', () {
      final tabs = OpenNotebooks();
      addTearDown(tabs.dispose);
      tabs
        ..open(notebook('a'))
        ..open(notebook('b'))
        ..activate('a')
        ..open(notebook('c'));
      expect(tabs.tabs.map((t) => t.id), ['a', 'c', 'b']);
      expect(tabs.activeId, 'c');
      tabs.open(notebook('b'));
      expect(tabs.length, 3);
      expect(tabs.activeId, 'b');
    });

    test('caps open tabs by closing the least recently used', () {
      final tabs = OpenNotebooks(maxTabs: 3);
      addTearDown(tabs.dispose);
      tabs
        ..open(notebook('a'))
        ..open(notebook('b'))
        ..open(notebook('c'))
        ..activate('a')
        ..open(notebook('d'));
      expect(tabs.tabs.map((t) => t.id), unorderedEquals(['a', 'c', 'd']));
    });

    test('closing the active tab shows its neighbour; views are remembered', () {
      final tabs = OpenNotebooks();
      addTearDown(tabs.dispose);
      tabs
        ..open(notebook('a'))
        ..open(notebook('b'))
        ..open(notebook('c'))
        ..activate('b')
        ..saveView('b', const EditorViewState(scale: 2, offset: Offset(1, 2), page: 3));
      expect(tabs.viewOf('b')?.page, 3);
      tabs.close('b');
      expect(tabs.activeId, 'c');
      expect(tabs.viewOf('b'), isNull);
      tabs.cycle();
      expect(tabs.activeId, 'a');
      tabs.cycle(backwards: true);
      expect(tabs.activeId, 'c');
      tabs
        ..rename('a', 'Renamed')
        ..move('a', 1);
      expect(tabs.tabs.map((t) => t.title), ['Notebook c', 'Renamed']);
      expect(tabs.takeVisited(), containsAll(['a', 'b', 'c']));
      expect(tabs.takeVisited(), isEmpty);
    });
  });

  testWidgets('tabs: open from the library, switch, keep each place, close', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    final physics = s.notebooks.create(
      title: 'Physics',
      kind: NotebookKind.paged,
      paper: PaperStyle.wideRuled,
      coverColor: 0,
    );
    for (var i = 0; i < 3; i++) {
      s.pages.addPage(physics.id, paper: const Paper(PaperStyle.wideRuled));
    }
    s.notebooks.create(
      title: 'Board',
      kind: NotebookKind.canvas,
      paper: PaperStyle.dotted,
      coverColor: 0,
    );
    await tester.pumpWidget(
      AppScope(
        services: s,
        child: MaterialApp(theme: AppTheme.light(), home: const LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await openCard(tester, 'Physics');
    expect(find.byType(EditorScreen), findsOneWidget);
    await nextPage(tester);
    await nextPage(tester);
    expect(find.text('3 / 4'), findsOneWidget);

    // Back to the library and open a second notebook: two tabs.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await openCard(tester, 'Board');
    expect(s.openNotebooks.length, 2);
    expect(find.byKey(ValueKey('tab-${physics.id}')), findsOneWidget);

    // Switch back: Physics is still on page 3.
    await tester.tap(find.byKey(ValueKey('tab-${physics.id}')));
    await tester.pumpAndSettle();
    expect(find.text('3 / 4'), findsOneWidget);

    // Ctrl+Tab cycles; Ctrl+W closes; closing the last tab leaves.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(s.openNotebooks.active?.title, 'Board');
    await tester.tap(find.byTooltip('Close tab').first);
    await tester.pumpAndSettle();
    expect(s.openNotebooks.length, 1);
    expect(find.byType(EditorScreen), findsOneWidget);
    s.openNotebooks.close(s.openNotebooks.activeId!);
    await tester.pumpAndSettle();
    expect(find.byType(EditorWorkspace), findsNothing);
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a link to a page of another notebook opens it at that page', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    final notes = s.notebooks.create(
      title: 'Notes',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final physics = s.notebooks.create(
      title: 'Physics',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    for (var i = 0; i < 3; i++) {
      s.pages.addPage(physics.id);
    }
    final target = s.pages.pagesOf(physics.id)[2];
    final page = s.pages.pagesOf(notes.id).single;
    s.elements.save([
      LinkElements.create(
        id: 'link',
        surfaceId: page.id,
        rect: Offset.zero & page.size,
        target: PageLinkTarget(notebookId: physics.id, pageId: target.id),
        createdAt: 1,
        z: -1,
      ),
    ]);
    s.preferences.stylusOnly = true; // A finger tap follows links.
    await tester.pumpWidget(
      AppScope(
        services: s,
        child: MaterialApp(theme: AppTheme.light(), home: const LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await openCard(tester, 'Notes');
    await tester.tapAt(const Offset(640, 450), kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();
    expect(s.openNotebooks.active?.id, physics.id);
    expect(find.text('3 / 4'), findsOneWidget);
  });

  for (final (size, strip, top) in const [
    // Tablet portrait: ← ▦ and the actions at the strip's ends, the tools
    // under it; two rows, not three.
    (Size(800, 1280), true, 52.0 + 48),
    // A phone held sideways: one row; the tabs are in ⋯.
    (Size(844, 390), false, 52.0),
  ]) {
    testWidgets('tabs at $size: chrome $top dp tall', (tester) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = AppServices.create(AppDatabase.inMemory());
      addTearDown(s.dispose);
      for (final title in ['Physics', 'Chemistry']) {
        final nb = s.notebooks.create(
          title: title,
          kind: NotebookKind.paged,
          paper: PaperStyle.wideRuled,
          coverColor: 0,
        );
        s.openNotebooks.open(nb);
      }
      await tester.pumpWidget(
        AppScope(
          services: s,
          child: MaterialApp(theme: AppTheme.light(), home: const EditorWorkspace()),
        ),
      );
      await tester.pumpAndSettle();
      final chrome = tester.widget<EditorChrome>(find.byType(EditorChrome));
      expect(chrome.layout.covered.top, top);
      expect(find.byType(NotebookTabStrip), strip ? findsOneWidget : findsNothing);
      if (strip) {
        final tab = tester.getCenter(find.byType(NotebookTabStrip)).dy;
        expect(tester.getCenter(find.byTooltip('Back')).dy, tab);
        expect(tester.getCenter(find.byTooltip('More options')).dy, tab);
      } else {
        await tester.tap(find.byTooltip('More options'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Open notebooks'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}
