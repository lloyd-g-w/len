import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/features/library/folder_tile.dart';
import 'package:len/features/library/library_sidebar.dart';
import 'package:len/features/library/new_notebook_sheet.dart';
import 'package:len/features/library/new_notebook_tile.dart';
import 'package:len/features/library/notebook_card.dart';
import 'package:len/features/library/notebook_list_tile.dart';
import 'package:len/ui/menus.dart';
import 'package:len/ui/sidebar_item.dart';

import 'ui_library_test.dart' show pumpLibrary;

Notebook addNotebook(AppServices s, String title, {String? folderId}) => s.notebooks.create(
  title: title,
  kind: NotebookKind.paged,
  paper: PaperStyle.wideRuled,
  coverColor: 0xFF3B5BDB,
  folderId: folderId,
);

/// Pumps the library with notebooks/folders created up front.
Future<AppServices> pumpSeeded(
  WidgetTester tester,
  void Function(AppServices s) seed, {
  Size size = const Size(1280, 800),
}) async {
  final services = AppServices.create(AppDatabase.inMemory());
  seed(services);
  return pumpLibrary(tester, services: services, size: size);
}

Future<void> openMenuOf(WidgetTester tester, String title) async {
  await tester.tap(
    find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(NotebookCard)),
      matching: find.byTooltip('More'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('create a folder, drag a notebook into it, navigate with breadcrumbs', (
    tester,
  ) async {
    final services = await pumpSeeded(tester, (s) => addNotebook(s, 'Algebra'));

    await tester.tap(find.byTooltip('New folder').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'School');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.byType(FolderTile), findsOneWidget);

    // Drag the notebook onto the folder with a mouse.
    final from = tester.getCenter(find.byType(NotebookCard));
    final to = tester.getCenter(find.byType(FolderTile));
    final gesture = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final folder = services.folders.list().single;
    expect(services.notebooks.list().single.folderId, folder.id);
    expect(find.byType(NotebookCard), findsNothing);

    await tester.tap(find.byType(FolderTile));
    await tester.pumpAndSettle();
    expect(find.text('Algebra'), findsOneWidget);
    // Breadcrumb back to the root.
    await tester.tap(find.widgetWithText(TextButton, 'Library'));
    await tester.pumpAndSettle();
    expect(find.byType(FolderTile), findsOneWidget);
    expect(find.text('Algebra'), findsNothing);
  });

  testWidgets('move via menu, favourite, duplicate, search across folders', (tester) async {
    late String schoolId;
    final services = await pumpSeeded(tester, (s) {
      schoolId = s.folders.create(name: 'School', color: 0xFF0CA678).id;
      addNotebook(s, 'Physics');
      addNotebook(s, 'Chemistry', folderId: schoolId);
    });

    await openMenuOf(tester, 'Physics');
    await tester.tap(find.text('Move to folder…'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('School')));
    await tester.pumpAndSettle();
    expect(services.notebooks.list().every((n) => n.folderId == schoolId), isTrue);

    await tester.tap(find.byType(FolderTile));
    await tester.pumpAndSettle();
    await openMenuOf(tester, 'Physics');
    await tester.tap(find.text('Add to favourites'));
    await tester.pumpAndSettle();
    await openMenuOf(tester, 'Chemistry');
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(find.text('Chemistry (copy)'), findsOneWidget);

    await tester.tap(find.text('Favourites').first);
    await tester.pumpAndSettle();
    expect(find.byType(NotebookCard), findsOneWidget);
    expect(find.text('Physics'), findsOneWidget);

    // Search from the library root finds notebooks inside folders.
    await tester.tap(find.text('Library').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'chem');
    await tester.pumpAndSettle();
    expect(find.byType(NotebookCard), findsNWidgets(2));
    expect(find.text('School'), findsWidgets); // Location subtitle.
  });

  testWidgets('at large text on a phone, card captions use the full width', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSeeded(tester, (s) => addNotebook(s, 'Travel plans'), size: const Size(390, 844));
    final card = find.byType(NotebookCard).first;
    final paragraphs = tester
        .renderObjectList<RenderParagraph>(
          find.descendant(of: card, matching: find.byType(RichText)),
        )
        .toList();
    // Title and caption: neither cut short.
    expect(paragraphs.where((p) => p.didExceedMaxLines), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at large text on a phone, folder names are not cut short', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSeeded(tester, (s) {
      s.folders.create(name: 'Sketches', color: 0xFFF08C00);
      s.folders.create(name: 'School', color: 0xFF3B5BDB);
    }, size: const Size(390, 844));
    final paragraphs = tester
        .renderObjectList<RenderParagraph>(
          find.descendant(of: find.byType(FolderTile), matching: find.byType(RichText)),
        )
        .toList();
    expect(paragraphs, isNotEmpty);
    expect(paragraphs.where((p) => p.didExceedMaxLines), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the New… tile starts the grid and opens the create flow', (tester) async {
    final semantics = tester.ensureSemantics();
    late String folderId;
    await pumpSeeded(tester, (s) {
      folderId = s.folders.create(name: 'School', color: 0xFF0CA678).id;
      s.notebooks.setFavorite(addNotebook(s, 'Fav').id, true);
      addNotebook(s, 'Inside', folderId: folderId);
    });
    final tile = find.byType(NewNotebookTile);
    expect(tile, findsOneWidget);
    // First in the grid: left of (and level with) the first notebook.
    expect(
      tester.getTopLeft(tile).dx,
      lessThan(tester.getTopLeft(find.byType(NotebookCard).first).dx),
    );
    expect(
      tester.getSemantics(tile),
      matchesSemantics(isButton: true, label: 'New notebook', hasTapAction: true),
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(NewNotebookSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(NewNotebookSheet))).pop();
    await tester.pumpAndSettle();

    // Inside folders too.
    await tester.tap(find.byType(FolderTile));
    await tester.pumpAndSettle();
    expect(tile, findsOneWidget);

    // Not in Favourites, the Trash, search results or the list layout.
    await tester.tap(find.text('Favourites').first);
    await tester.pumpAndSettle();
    expect(find.byType(NotebookCard), findsOneWidget);
    expect(tile, findsNothing);
    await tester.tap(find.text('Trash').first);
    await tester.pumpAndSettle();
    expect(tile, findsNothing);
    await tester.tap(find.text('Library').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Fav');
    await tester.pumpAndSettle();
    expect(tile, findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(tile, findsOneWidget);
    await tester.tap(find.byTooltip('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select…').last);
    await tester.pumpAndSettle();
    expect(tile, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tile, findsOneWidget);
    await tester.tap(find.byTooltip('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List').last);
    await tester.pumpAndSettle();
    expect(tile, findsNothing);
    semantics.dispose();
  });

  testWidgets('list view and sort order persist as preferences', (tester) async {
    final services = await pumpSeeded(tester, (s) {
      addNotebook(s, 'Banana');
      addNotebook(s, 'apple');
      addNotebook(s, 'Cherry');
    });
    await tester.tap(find.byTooltip('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List').last);
    await tester.pumpAndSettle();
    expect(find.byType(NotebookListTile), findsNWidgets(3));
    expect(services.preferences.libraryLayout, LibraryLayout.list);

    await tester.tap(find.byTooltip('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((w) => w is MenuRow && w.label == 'Name'));
    await tester.pumpAndSettle();
    expect(services.preferences.librarySort, LibrarySort.name);
    final titles = tester
        .widgetList<NotebookListTile>(find.byType(NotebookListTile))
        .map((t) => t.notebook.title);
    expect(titles, ['apple', 'Banana', 'Cherry']);
  });

  testWidgets('keyboard: Ctrl+N new, Ctrl+F search, Delete trashes the focused notebook', (
    tester,
  ) async {
    final services = await pumpSeeded(tester, (s) => addNotebook(s, 'Keys'));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(NewNotebookSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(NewNotebookSheet))).pop();
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    // Focus the card (as Tab would) and press Delete.
    final inner = find.descendant(of: find.byType(NotebookCard), matching: find.byType(Builder));
    Focus.of(tester.element(inner.first)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(services.notebooks.list(), isEmpty);
    expect(services.notebooks.trashed().single.title, 'Keys');
    expect(find.text('“Keys” moved to the trash'), findsOneWidget);
  });

  testWidgets('deleting a folder sends its notebooks to the trash', (tester) async {
    final services = await pumpSeeded(tester, (s) {
      final f = s.folders.create(name: 'Old', color: 0xFF495057);
      addNotebook(s, 'Inside', folderId: f.id);
    });
    await tester.tap(find.byTooltip('Folder options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete folder…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(services.folders.list(), isEmpty);
    expect(services.notebooks.trashed().single.title, 'Inside');
    expect(find.text('1'), findsWidgets); // Trash count in the sidebar.
  });

  testWidgets('phone layout: the drawer goes between sections', (tester) async {
    await pumpSeeded(tester, (s) => addNotebook(s, 'Pocket'), size: const Size(390, 844));
    expect(find.byType(LibrarySidebar), findsNothing);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.text('Favourites'));
    await tester.pumpAndSettle();
    expect(find.byType(LibrarySidebar), findsNothing, reason: 'the drawer closes');
    expect(find.text('No favourites yet'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing, reason: 'it creates in the library');
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();
    expect(find.text('Trash is empty'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    // New folder from the drawer closes the drawer under its sheet.
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    expect(find.byType(LibrarySidebar), findsNothing);
    expect(find.text('New folder'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phones: searching hides ⊕', (tester) async {
    await pumpSeeded(tester, (s) => addNotebook(s, 'Pocket'), size: const Size(390, 844));
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No results'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('settings change the theme mode app-wide', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    await tester.pumpWidget(LenApp(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app().themeMode, ThemeMode.dark);
    expect(services.preferences.themeMode, ThemePreference.dark);

    // Every section in one column, wide windows too.
    expect(find.byType(SidebarItem), findsNothing);
    await tester.ensureVisible(find.text('Tap to undo and redo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap to undo and redo'));
    await tester.pumpAndSettle();
    expect(services.preferences.fingerTapUndo, isFalse);
  });

  testWidgets('narrow settings list every section in one column', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    await tester.pumpWidget(LenApp(services: services));
    await tester.pumpAndSettle();
    // Below 840 dp the sidebar is a drawer.
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SidebarItem), findsNothing);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Tap to undo and redo'), findsOneWidget);
  });

  testWidgets('long-press on touch opens the context menu; right-click too', (tester) async {
    await pumpSeeded(tester, (s) => addNotebook(s, 'Touchy'));
    await tester.longPress(find.byType(NotebookCard));
    await tester.pumpAndSettle();
    expect(find.text('Move to trash'), findsOneWidget);
    await tester.tapAt(const Offset(5, 795));
    await tester.pumpAndSettle();
    expect(find.text('Move to trash'), findsNothing);

    await tester.tap(find.byType(NotebookCard), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Duplicate'), findsOneWidget);
  });

  testWidgets('phones: a long press on ⊕ offers a folder, a canvas or a PDF', (tester) async {
    final s = await pumpSeeded(
      tester,
      (s) => addNotebook(s, 'Algebra'),
      size: const Size(390, 844),
    );
    await tester.longPress(find.byTooltip('New notebook'));
    await tester.pumpAndSettle();
    for (final item in ['New notebook', 'New canvas', 'Import PDF…', 'New folder…']) {
      expect(find.text(item), findsOneWidget);
    }
    await tester.tap(find.text('New folder…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'School');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(s.folders.list().map((f) => f.name), ['School']);
    expect(tester.takeException(), isNull);
  });
}
