import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/tabs/open_notebooks.dart';
import 'package:len/features/editor/tabs/workspace_memory.dart';
import 'package:len/features/library/recent_row.dart';

import 'library_ui_test.dart' show addNotebook, pumpSeeded;

/// Keeps a workspace of [ids] (active [active], [split] in the second
/// pane) in [s]'s settings as an editor shown on another launch would.
void keepWorkspace(AppServices s, List<String> ids, {String? active, String? split}) {
  final tabs = OpenNotebooks();
  final memory = WorkspaceMemory(settings: s.settings, tabs: tabs, isClosed: () => false);
  for (final id in ids) {
    tabs.open(s.notebooks.get(id)!);
  }
  if (active != null) tabs.activate(active);
  if (split != null) tabs.openSplit(split);
  tabs.splitFraction = 0.6;
  memory.shown = true;
  memory.dispose();
  tabs.dispose();
}

void main() {
  group('WorkspaceMemory (R7-7)', () {
    late AppServices s;
    setUp(() => s = AppServices.create(AppDatabase.inMemory()));
    tearDown(() => s.dispose());

    test('keeps tabs, the active one and the split; restores them on launch', () {
      final a = addNotebook(s, 'A'), b = addNotebook(s, 'B'), c = addNotebook(s, 'C');
      keepWorkspace(s, [a.id, b.id, c.id], active: b.id, split: c.id);

      final tabs = OpenNotebooks();
      addTearDown(tabs.dispose);
      final memory = WorkspaceMemory(settings: s.settings, tabs: tabs, isClosed: () => false);
      addTearDown(memory.dispose);
      final shown = memory.restore(s.notebooks.get);
      expect(shown?.id, b.id);
      expect([for (final t in tabs.tabs) t.title], ['A', 'B', 'C']);
      expect(tabs.activeId, b.id);
      expect(tabs.splitId, c.id);
      expect(tabs.splitFraction, 0.6);
    });

    test('trashed and deleted notebooks are left out; nothing kept, nothing opens', () {
      final a = addNotebook(s, 'A'), b = addNotebook(s, 'B');
      keepWorkspace(s, [a.id, b.id], active: b.id);
      s.notebooks.trash(b.id);
      final tabs = OpenNotebooks();
      addTearDown(tabs.dispose);
      final memory = WorkspaceMemory(settings: s.settings, tabs: tabs, isClosed: () => false);
      addTearDown(memory.dispose);
      expect(memory.restore(s.notebooks.get)?.id, a.id);
      expect(tabs.length, 1);

      s.settings.workspace = null;
      expect(memory.restore(s.notebooks.get), isNull);
      s.settings.workspace = '{not json';
      expect(memory.restore(s.notebooks.get), isNull);
    });

    test('going back to the library forgets the workspace; recents keep 16', () {
      final tabs = OpenNotebooks();
      addTearDown(tabs.dispose);
      final memory = WorkspaceMemory(settings: s.settings, tabs: tabs, isClosed: () => false);
      addTearDown(memory.dispose);
      final notebooks = [for (var i = 0; i < 10; i++) addNotebook(s, 'N$i')];
      memory.shown = true;
      for (final n in notebooks) {
        tabs.open(n);
      }
      tabs.activate(notebooks[3].id);
      expect(s.settings.workspace, isNotNull);
      expect(memory.recent.first, notebooks[3].id);
      for (var i = 0; i < 20; i++) {
        memory.noteOpened('id$i');
      }
      expect(memory.recent, hasLength(WorkspaceMemory.recentCount));
      memory.shown = false;
      expect(s.settings.workspace, isNull);
    });
  });

  testWidgets('launch reopens the workspace; Back shows the library and forgets it', (
    tester,
  ) async {
    final s = await pumpSeeded(tester, (s) {
      final a = addNotebook(s, 'Algebra'), b = addNotebook(s, 'Biology');
      keepWorkspace(s, [a.id, b.id], active: a.id);
    });
    expect(find.byType(EditorScreen), findsOneWidget);
    expect(s.openNotebooks.active?.title, 'Algebra');
    expect(s.openNotebooks.length, 2);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNothing);
    expect(s.settings.workspace, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Recent row at the root: notebooks from folders, one tap (R7-6)', (tester) async {
    final s = await pumpSeeded(tester, (s) {
      final school = s.folders.create(name: 'School', color: 0xFF0CA678);
      final algebra = addNotebook(s, 'Algebra', folderId: school.id);
      final biology = addNotebook(s, 'Biology');
      s.settings.recentNotebooks = [algebra.id, biology.id];
    });
    expect(find.text('Recent'), findsOneWidget);
    final tiles = find.byType(RecentTile);
    expect(tiles, findsNWidgets(2));
    expect(find.descendant(of: tiles.first, matching: find.text('School')), findsOneWidget);
    // No caption at the top level (R8-10).
    expect(find.descendant(of: tiles.last, matching: find.text('Library')), findsNothing);
    // Above the folders.
    expect(
      tester.getTopLeft(find.text('Recent')).dy,
      lessThan(tester.getTopLeft(find.text('School').last).dy),
    );

    await tester.tap(find.descendant(of: tiles.last, matching: find.text('Biology')));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    // Most recent first.
    final titles = [
      for (final t in tester.widgetList<RecentTile>(find.byType(RecentTile))) t.notebook.title,
    ];
    expect(titles, ['Biology', 'Algebra']);
    expect(s.workspace.recent.first, s.notebooks.list().firstWhere((n) => n.title == 'Biology').id);

    // Not inside folders.
    await tester.tap(find.text('School').last);
    await tester.pumpAndSettle();
    expect(find.text('Recent'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no Recent row while everything lives at the root', (tester) async {
    await pumpSeeded(tester, (s) {
      final a = addNotebook(s, 'Algebra'), b = addNotebook(s, 'Biology');
      s.settings.recentNotebooks = [a.id, b.id];
    });
    expect(find.byType(RecentRow), findsNothing);
  });

  testWidgets('a phone held sideways: Recent leads the folder strip, a menu', (tester) async {
    await pumpSeeded(tester, size: const Size(844, 390), (s) {
      final school = s.folders.create(name: 'School', color: 0xFF0CA678);
      final algebra = addNotebook(s, 'Algebra', folderId: school.id);
      final biology = addNotebook(s, 'Biology');
      s.settings.recentNotebooks = [algebra.id, biology.id];
    });
    expect(find.byType(RecentRow), findsNothing);
    final tile = find.byType(RecentStripTile);
    // Captioned with the latest one (R8-10).
    expect(find.descendant(of: tile, matching: find.text('Algebra')), findsOneWidget);
    // In the one row of chrome, before the folders.
    expect(tester.getRect(tile).bottom, lessThan(80));
    expect(tester.getTopLeft(tile).dx, lessThan(tester.getTopLeft(find.text('School')).dx));
    expect(tester.takeException(), isNull);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    // The menu says where each lives.
    expect(find.text('School'), findsNWidgets(2));
    await tester.tap(find.text('Algebra').last);
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trashed notebooks leave no gap in Recent (R8-10)', (tester) async {
    await pumpSeeded(tester, (s) {
      final school = s.folders.create(name: 'School', color: 0xFF0CA678);
      final notebooks = [for (var i = 0; i < 12; i++) addNotebook(s, 'N$i', folderId: school.id)];
      for (final n in notebooks.take(3)) {
        s.notebooks.trash(n.id);
      }
      s.settings.recentNotebooks = [for (final n in notebooks) n.id];
    });
    final titles = [
      for (final t in tester.widgetList<RecentTile>(find.byType(RecentTile))) t.notebook.title,
    ];
    expect(titles, [for (var i = 3; i < 11; i++) 'N$i']);
  });
}
