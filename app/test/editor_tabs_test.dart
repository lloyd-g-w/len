import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/tabs/editor_workspace.dart';
import 'package:len/features/editor/tabs/open_notebooks.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/ui/app_theme.dart';

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
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
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
}
