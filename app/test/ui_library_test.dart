import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/library/new_notebook_sheet.dart';
import 'package:len/sync/sync_api.dart';
import 'package:len/ui/app_theme.dart';

import 'support/fake_server.dart' show FakeServer;

/// Pumps the library with fresh in-memory services. Sync stays unconfigured
/// and is never started (that would leave a periodic timer running).
Future<AppServices> pumpLibrary(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  ThemeMode themeMode = ThemeMode.light,
  AppServices? services,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  services ??= AppServices.create(AppDatabase.inMemory());
  addTearDown(services.dispose);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        home: const LibraryScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return services;
}

/// Creates a notebook through the "New" sheet; ends inside the editor.
Future<void> createNotebook(WidgetTester tester, String title, {bool canvas = false}) async {
  final empty = find.text('New notebook');
  await tester.tap(empty.evaluate().isNotEmpty ? empty : find.text('New'));
  await tester.pumpAndSettle();
  if (canvas) {
    await tester.tap(find.text('Infinite canvas'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(
    find.descendant(of: find.byType(NewNotebookSheet), matching: find.byType(TextField)),
    title,
  );
  await tester.tap(find.text('Create'));
  await tester.pumpAndSettle();
}

/// Draws a short mouse stroke across the middle of the screen.
Future<void> drawStroke(WidgetTester tester) async {
  final centre = tester.getCenter(find.byType(EditorScreen));
  final gesture = await tester.startGesture(centre, kind: PointerDeviceKind.mouse);
  for (var i = 1; i <= 10; i++) {
    await gesture.moveTo(centre + Offset(i * 8.0, i * 3.0));
  }
  await gesture.up();
  await tester.pump();
}

bool isToolSelected(WidgetTester tester, String tooltip) {
  final button = tester.widget<IconButton>(
    find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton)).first,
  );
  return button.isSelected ?? false;
}

void main() {
  testWidgets('create a notebook from the empty library, draw, and go back', (tester) async {
    final services = await pumpLibrary(tester);
    expect(find.text('Nothing here yet'), findsOneWidget);

    await createNotebook(tester, 'Physics');
    expect(find.byType(EditorScreen), findsOneWidget);
    expect(find.text('Physics'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);

    await drawStroke(tester);
    await tester.tap(find.byTooltip('Add page after this one'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNothing);
    expect(find.text('Physics'), findsOneWidget);
    expect(services.notebooks.list().single.title, 'Physics');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the new sheet sets the first page template and offers PDF import', (tester) async {
    final services = await pumpLibrary(tester);
    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();
    expect(find.text('Import PDF…'), findsOneWidget);

    final swatch = find.text('Small grid');
    await tester.ensureVisible(swatch);
    await tester.tap(swatch);
    await tester.pumpAndSettle();
    // The summary reflects the choice.
    expect(find.text('Small grid · White · A4 portrait'), findsOneWidget);

    // Canvases have a paper colour but no page size.
    await tester.tap(find.text('Infinite canvas'));
    await tester.pumpAndSettle();
    expect(find.text('Small grid · White · Infinite canvas'), findsOneWidget);
    expect(find.text('Page size'), findsNothing);
    await tester.tap(find.text('Notebook'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    final notebook = services.notebooks.list().single;
    expect(services.pages.pagesOf(notebook.id).single.paper, PaperStyle.gridSmall);
    expect(tester.takeException(), isNull);
  });

  testWidgets('infinite canvas opens on a narrow phone without overflow', (tester) async {
    await pumpLibrary(tester, size: const Size(320, 640), themeMode: ThemeMode.dark);
    await createNotebook(tester, 'A rather long canvas title that must ellipsize', canvas: true);
    expect(find.byType(EditorScreen), findsOneWidget);
    expect(find.text('1 / 1'), findsNothing); // No page navigator on canvases.
    await drawStroke(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tool shortcuts fire on the canvas but not while typing', (tester) async {
    await pumpLibrary(tester);
    await createNotebook(tester, 'Keys');
    expect(isToolSelected(tester, 'Pen (P)'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    expect(isToolSelected(tester, 'Highlighter (H)'), isTrue);

    // Typing "e" into the rename dialog must not pick the eraser.
    await tester.tap(find.text('Keys'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(isToolSelected(tester, 'Highlighter (H)'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(isToolSelected(tester, 'Eraser (E)'), isTrue);
  });

  testWidgets('rename, trash, restore and delete forever from the card menu', (tester) async {
    final services = await pumpLibrary(tester);
    await createNotebook(tester, 'Draft');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Final');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Final'), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();
    expect(services.notebooks.list(), isEmpty);
    expect(find.text('Nothing here yet'), findsOneWidget);

    // Restore from the trash.
    await tester.tap(find.text('Trash').first);
    await tester.pumpAndSettle();
    expect(find.text('Final'), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(services.notebooks.list().single.title, 'Final');
    expect(find.text('Trash is empty'), findsOneWidget);

    // Trash again, then delete forever.
    await tester.tap(find.text('Library').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trash').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete forever'));
    await tester.pumpAndSettle();
    expect(services.notebooks.trashed(), isEmpty);
    expect(find.text('Trash is empty'), findsOneWidget);
  });

  testWidgets('remote delete closes the editor and any dialog on top of it', (tester) async {
    final server = FakeServer();
    AppServices device() {
      final services = AppServices.create(
        AppDatabase.inMemory(),
        syncApiFactory: (url, token) => SyncApi(baseUrl: url, token: token, client: server.client),
      );
      services.sync.configure(url: 'http://sync.test', token: FakeServer.token);
      return services;
    }

    final local = device();
    final other = device();
    addTearDown(other.dispose);
    await pumpLibrary(tester, services: local);
    await createNotebook(tester, 'Shared');
    await tester.runAsync(() async {
      await local.sync.syncNow();
      await other.sync.syncNow();
    });
    other.notebooks.delete(other.notebooks.list().single.id);

    // Rename dialog open while the deletion arrives.
    await tester.tap(find.text('Shared'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.runAsync(() async {
      await other.sync.syncNow();
      await local.sync.syncNow();
    });
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(EditorScreen), findsNothing);
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.textContaining('deleted on another device'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
