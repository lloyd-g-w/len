import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/versions/versions.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/chrome/editor_menu_actions.dart';
import 'package:len/features/editor/chrome/editor_more_menu.dart';
import 'package:len/features/history/version_history_sheet.dart';
import 'package:len/features/history/version_row_text.dart';
import 'package:len/features/library/library_menus.dart';
import 'package:len/ui/app_theme.dart';

import 'support/real_async.dart';

class _Clock extends Clock {
  int now = DateTime(2026, 10, 1, 14, 2).millisecondsSinceEpoch;
  int _ids = 0;

  @override
  int nowMs() => now;

  @override
  String newId() => 'id${_ids++}';
}

Stroke _ink(String id, String surface, {double x = 10}) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF000000,
  width: 3,
  points: [StrokePoint(x, 10, 0.5), StrokePoint(x + 30, 40, 0.5)],
  createdAt: 1,
);

void main() {
  late _Clock clock;
  late AppServices s;
  late Notebook notebook;
  late List<String> pages;

  Set<String> strokesOn(String surface) => {
    for (final row in s.database.db.select(
      'SELECT id FROM strokes WHERE surface_id = ? AND deleted = 0',
      [surface],
    ))
      row['id'] as String,
  };

  /// Sets up a notebook of two pages with a version yesterday and one
  /// today (real time: packs are hashed in an isolate).
  Future<(NotebookVersion, NotebookVersion)> twoVersions(WidgetTester tester) async {
    clock = _Clock();
    s = AppServices.create(AppDatabase.inMemory(), clock: clock);
    addTearDown(s.dispose);
    notebook = s.notebooks.create(
      title: 'Lab book',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0xFF336699,
    );
    s.pages.addPage(notebook.id);
    pages = [for (final p in s.pages.pagesOf(notebook.id)) p.id];
    late NotebookVersion old, recent;
    await tester.runAsync(() async {
      s.strokes.save([_ink('a', pages.first)]);
      clock.now -= const Duration(days: 1).inMilliseconds;
      old = (await s.versions.record(notebook.id))!;
      clock.now += const Duration(days: 1).inMilliseconds;
      s.strokes.save([_ink('b', pages.last), _ink('c', pages.last, x: 60)]);
      recent = (await s.versions.record(notebook.id))!;
    });
    return (old, recent);
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showVersionHistory(context, s, notebook.id),
                child: const Text('History'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
  }

  testWidgets('the timeline: days, times, devices and what changed', (tester) async {
    final (old, recent) = await twoVersions(tester);
    await open(tester);
    expect(find.text('Version history'), findsOneWidget);
    expect(find.text('Lab book'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.byKey(ValueKey('version-${recent.id}')), findsOneWidget);
    // A row's words are one render object (VersionRowText).
    Finder words({String? time, String? details}) => find.byWidgetPredicate(
      (w) => w is VersionRowText && (w.time == time || w.details == details),
    );
    expect(words(details: 'This device, 1 page edited, 2 strokes added'), findsOneWidget);
    expect(words(details: 'This device, 2 pages, 1 stroke'), findsOneWidget, reason: 'the first');
    expect(words(time: '14:02'), findsNWidgets(2));
    // Newest first.
    expect(
      tester.getTopLeft(find.byKey(ValueKey('version-${recent.id}'))).dy,
      lessThan(tester.getTopLeft(find.byKey(ValueKey('version-${old.id}'))).dy),
    );
  });

  testWidgets('no versions yet says how they come', (tester) async {
    clock = _Clock();
    s = AppServices.create(AppDatabase.inMemory(), clock: clock);
    addTearDown(s.dispose);
    notebook = s.notebooks.create(
      title: 'Empty',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    await open(tester);
    expect(find.textContaining('No versions yet'), findsOneWidget);
  });

  testWidgets('Save version… names one', (tester) async {
    await twoVersions(tester);
    clock.now += 60000;
    await open(tester);
    await tester.tap(find.text('Save version…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Before the exam');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    await pumpUntil(
      tester,
      () => s.versions.of(notebook.id).first.kind == VersionKind.named,
      reason: 'the named version',
    );
    await tester.pumpAndSettle();
    expect(find.text('Before the exam'), findsOneWidget);
  });

  testWidgets('preview, restore, and undo through the version saved before', (tester) async {
    final (old, _) = await twoVersions(tester);
    await open(tester);
    await tester.tap(find.byKey(ValueKey('version-${old.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Yesterday, 14:02'), findsOneWidget);
    expect(find.byKey(ValueKey('version-page-${pages.first}')), findsOneWidget);
    expect(find.byKey(ValueKey('version-page-${pages.last}')), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Restore this version?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Restore'),
      ),
    );
    await pumpUntil(tester, () => find.textContaining('Restored to').evaluate().isNotEmpty);
    expect(strokesOn(pages.last), isEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Version history'), findsNothing, reason: 'back to the notebook');
    expect(s.versions.of(notebook.id).first.kind, VersionKind.restore);

    await tester.tap(find.text('Undo'));
    await pumpUntil(tester, () => strokesOn(pages.last).length == 2, reason: 'undone');
  });

  testWidgets('one page restores from its page view', (tester) async {
    final (old, _) = await twoVersions(tester);
    await open(tester);
    await tester.tap(find.byKey(ValueKey('version-${old.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('version-page-${pages.last}')));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 2'), findsOneWidget);
    await tester.tap(find.text('Restore this page'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Restore page'));
    await pumpUntil(tester, () => find.textContaining('Page restored').evaluate().isNotEmpty);
    // The version saved before restoring gets its thumbnail (loads take turns).
    await tester.pumpAndSettle();
    expect(strokesOn(pages.last), isEmpty);
    expect(strokesOn(pages.first), {'a'});
  });

  testWidgets('Copy as new notebook and Delete older versions…', (tester) async {
    final (old, recent) = await twoVersions(tester);
    await open(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('version-${recent.id}')),
        matching: find.byTooltip('Version options'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy as new notebook'));
    await pumpUntil(tester, () => s.notebooks.list().length == 2, reason: 'the copy');
    final copy = s.notebooks.list().firstWhere((n) => n.id != notebook.id);
    expect(copy.title, startsWith('Lab book ('));

    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('version-${recent.id}')),
        matching: find.byTooltip('Version options'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete older versions…'));
    await tester.pumpAndSettle();
    expect(find.text('Delete older versions?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('version-${old.id}')), findsNothing);
    expect(s.versions.of(notebook.id).map((v) => v.id), [recent.id]);
  });

  test('the library offers Version history… for notebooks, not in the trash', () {
    const live = Notebook(
      id: 'n',
      title: 'N',
      kind: NotebookKind.paged,
      paper: Paper.blank,
      coverColor: 0,
      createdAt: 0,
      updatedAt: 0,
    );
    bool offers(Notebook n) =>
        notebookMenuItems(n)
            .whereType<MenuRow<NotebookAction>>()
            .any((r) => r.value == NotebookAction.history);
    expect(offers(live), isTrue);
    expect(offers(live.copyWith(trashedAt: 1)), isFalse);
  });

  testWidgets('the editor’s ⋯ menu opens the history (Save version… is in its header)', (
    tester,
  ) async {
    var history = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: EditorMoreMenu(
              actions: EditorMenuActions(
                onBack: () {},
                onRename: () {},
                onFocusMode: () {},
                stylusOnly: null,
                onStylusOnly: (_) {},
                placement: ToolbarPlacement.docked,
                onPlacement: (_) {},
                onSettings: () {},
                onSearch: () {},
                zoomWindow: false,
                onZoomWindow: () {},
                onVersionHistory: () => history++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Save version…'), findsNothing);
    await tester.tap(find.text('Version history…'));
    await tester.pumpAndSettle();
    expect(history, 1);
  });
}
