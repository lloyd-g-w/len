import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/chrome/editor_chrome.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/tabs/editor_workspace.dart';
import 'package:len/features/editor/tabs/notebook_tab_strip.dart';
import 'package:len/features/editor/tabs/open_notebooks.dart';
import 'package:len/features/settings/general_settings.dart';
import 'package:len/ui/app_theme.dart';

Notebook notebook(String id) => Notebook(
  id: id,
  title: 'Notebook $id',
  kind: NotebookKind.paged,
  paper: Paper.blank,
  coverColor: 0,
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  group('OpenNotebooks without tabs', () {
    test('opening replaces the open notebook', () {
      final tabs = OpenNotebooks()..tabbed = false;
      addTearDown(tabs.dispose);
      tabs
        ..open(notebook('a'))
        ..open(notebook('b'));
      expect(tabs.tabs.map((t) => t.id), ['b']);
      expect(tabs.activeId, 'b');
      tabs.cycle();
      expect(tabs.activeId, 'b');
    });

    test('turning tabs off keeps only the active notebook, and the split of another closes', () {
      final tabs = OpenNotebooks();
      addTearDown(tabs.dispose);
      tabs
        ..open(notebook('a'))
        ..open(notebook('b'))
        ..open(notebook('c'))
        ..activate('b')
        ..openSplit('c')
        ..saveView('a', const EditorViewState(scale: 2, offset: Offset.zero, page: 1));
      var notified = 0;
      tabs
        ..addListener(() => notified++)
        ..tabbed = false;
      expect(tabs.tabs.map((t) => t.id), ['b']);
      expect(tabs.activeId, 'b');
      expect(tabs.splitId, isNull);
      expect(tabs.viewOf('a'), isNull);
      expect(notified, 1);

      // Back on: notebooks open in tabs again.
      tabs
        ..tabbed = true
        ..open(notebook('d'));
      expect(tabs.tabs.map((t) => t.id), ['b', 'd']);
      expect(notified, 3);
    });

    test('a split of the same notebook stays', () {
      final tabs = OpenNotebooks();
      addTearDown(tabs.dispose);
      tabs
        ..open(notebook('a'))
        ..open(notebook('b'))
        ..openSplit('b')
        ..tabbed = false;
      expect(tabs.splitId, 'b');
    });
  });

  testWidgets('the General switch turns tabs off and on', (tester) async {
    final s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    s.openNotebooks
      ..open(notebook('a'))
      ..open(notebook('b'));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(child: GeneralSettings(preferences: s.preferences)),
        ),
      ),
    );
    expect(s.preferences.notebookTabs, isTrue);
    await tester.tap(find.text('Notebook tabs'));
    await tester.pump();
    expect(s.settings.notebookTabs, isFalse);
    expect(s.openNotebooks.tabbed, isFalse);
    expect(s.openNotebooks.tabs.map((t) => t.id), ['b']);
    await tester.tap(find.text('Notebook tabs'));
    await tester.pump();
    expect(s.openNotebooks.tabbed, isTrue);
  });

  testWidgets('without tabs: no strip, no tab shortcuts, opening replaces; live both ways', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    final books = [
      for (final title in ['Physics', 'Chemistry', 'Biology'])
        s.notebooks.create(
          title: title,
          kind: NotebookKind.paged,
          paper: PaperStyle.wideRuled,
          coverColor: 0,
        ),
    ];
    s.openNotebooks.open(books[0]);
    await tester.pumpWidget(
      AppScope(
        services: s,
        child: MaterialApp(theme: AppTheme.light(), home: const EditorWorkspace()),
      ),
    );
    await tester.pumpAndSettle();
    double top() => tester.widget<EditorChrome>(find.byType(EditorChrome)).layout.covered.top;
    final single = top();

    s.openNotebooks.open(books[1]);
    await tester.pumpAndSettle();
    expect(find.byType(NotebookTabStrip), findsOneWidget);

    // Off: the strip goes, the bar is as tall as with one notebook, and
    // only the notebook shown stays open.
    s.preferences.notebookTabs = false;
    await tester.pumpAndSettle();
    expect(find.byType(NotebookTabStrip), findsNothing);
    expect(top(), single);
    expect(s.openNotebooks.tabs.map((t) => t.title), ['Chemistry']);
    expect(find.byType(EditorScreen), findsOneWidget);

    // Opening another replaces it; Ctrl+W doesn't close it, and ⋯ lists
    // no open notebooks.
    final context = tester.element(find.byType(EditorScreen));
    await openNotebook(context, books[2]);
    await tester.pumpAndSettle();
    expect(s.openNotebooks.tabs.map((t) => t.title), ['Biology']);
    expect(find.byType(NotebookTabStrip), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(s.openNotebooks.length, 1);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Open notebooks'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // On again: notebooks open in tabs at once.
    s.preferences.notebookTabs = true;
    await tester.pumpAndSettle();
    s.openNotebooks.open(books[0]);
    await tester.pumpAndSettle();
    expect(s.openNotebooks.length, 2);
    expect(find.byType(NotebookTabStrip), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
