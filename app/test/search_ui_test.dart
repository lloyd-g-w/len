import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/canvas/canvas_view.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/search/editor/editor_search_bar.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/sync/sync_api.dart';
import 'package:len/ui/app_theme.dart';

import 'content_golden_test.dart' show loadFonts;
import 'content_tools_ui_test.dart' show pinCanvasView;
import 'support/fake_server.dart' show FakeServer, apiFor;
import 'ui_library_test.dart' show pumpLibrary;

/// An auto-width text box sized by the app's layout.
SurfaceElement textBox(String id, String surface, String text, Offset at) {
  final data = TextData(text: text, autoWidth: true);
  final width = TextLayout.naturalWidth(data);
  return SurfaceElement(
    id: id,
    surfaceId: surface,
    type: 'text',
    rect: Rect.fromLTWH(at.dx, at.dy, width, TextLayout.heightOf(data, width)),
    z: 1,
    createdAt: 1,
    data: data.toJson(),
  );
}

/// Biology (3 pages), Chemistry (1 page) and an "Ideas" canvas, with text
/// boxes mentioning "light".
({Notebook biology, Notebook chemistry, Notebook ideas}) seed(AppServices s) {
  Notebook paged(String title, int cover) => s.notebooks.create(
    title: title,
    kind: NotebookKind.paged,
    paper: PaperStyle.collegeRuled,
    coverColor: cover,
    firstPage: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)),
  );
  final biology = paged('Biology', 0xFF2F9E44);
  final b1 = s.pages.pagesOf(biology.id).single;
  s.pages.addPage(biology.id, template: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)));
  final b3 = s.pages.addPage(
    biology.id,
    template: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)),
  );
  final chemistry = paged('Chemistry', 0xFFE8590C);
  final c1 = s.pages.pagesOf(chemistry.id).single;
  final ideas = s.notebooks.create(
    title: 'Ideas',
    kind: NotebookKind.canvas,
    paper: PaperStyle.dotted,
    coverColor: 0xFF3B5BDB,
  );
  s.elements.save([
    textBox('b1', b1.id, 'Cell structure and organelles', const Offset(90, 140)),
    textBox('b3', b3.id, 'Photosynthesis converts light energy', const Offset(90, 700)),
    textBox('b3b', b3.id, 'Cells divide by mitosis', const Offset(90, 300)),
    textBox('c1', c1.id, 'Light reactions happen in the chlorophyll', const Offset(90, 200)),
    textBox('i1', ideas.id, 'A light bulb moment', const Offset(3000, 2000)),
  ]);
  return (biology: biology, chemistry: chemistry, ideas: ideas);
}

Future<AppServices> pumpEditorFor(
  WidgetTester tester,
  AppServices services,
  Notebook notebook, {
  Size size = const Size(900, 1200),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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

Future<void> typeSearch(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).last, text);
  await tester.pump(const Duration(milliseconds: 200)); // Debounce.
  await tester.pumpAndSettle();
}

int currentPage(WidgetTester tester) =>
    tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller.currentPage;

void main() {
  testWidgets('library: full-text results grouped by notebook open the page and highlight', (
    tester,
  ) async {
    await loadFonts();
    final services = AppServices.create(AppDatabase.inMemory());
    final nbs = seed(services);
    await pumpLibrary(tester, services: services, size: const Size(1280, 860));

    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'light');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('In notebooks · 3 matches'), findsOneWidget);
    expect(find.text('Page 3'), findsOneWidget);
    expect(find.text('Canvas'), findsOneWidget);
    await expectLater(find.byType(LibraryScreen), matchesGoldenFile('goldens/search_library.png'));

    await tester.tap(find.textContaining('Photosynthesis', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.byType(EditorSearchBar), findsOneWidget);
    expect(find.text('1 of 1'), findsOneWidget);
    expect(currentPage(tester), 2);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'light',
      reason: 'the editor searches what the library searched',
    );
    await expectLater(find.byType(EditorScreen), matchesGoldenFile('goldens/search_editor.png'));
    expect(nbs.biology.id, isNotEmpty);
  });

  testWidgets('editor: Ctrl+F, next / previous across pages, Esc closes', (tester) async {
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    final nbs = seed(services);
    await pumpEditorFor(tester, services, nbs.biology);

    expect(find.byType(EditorSearchBar), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(EditorSearchBar), findsOneWidget);

    await typeSearch(tester, 'cell');
    expect(find.text('2 matches'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
    expect(currentPage(tester), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);
    expect(currentPage(tester), 2);

    await tester.tap(find.byTooltip('Previous (Shift+Enter)'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
    expect(currentPage(tester), 0);

    // Tapping a listed match jumps to it.
    await tester.tap(find.textContaining('mitosis', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);

    await typeSearch(tester, 'zebra');
    expect(find.text('No matches'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(EditorSearchBar), findsNothing);
  });

  testWidgets('canvas: the search button finds a far-away text box and pans to it', (tester) async {
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    final nbs = seed(services);
    pinCanvasView(services, nbs.ideas.id, const Size(900, 1200));
    await pumpEditorFor(tester, services, nbs.ideas);
    final viewport = tester.widget<CanvasView>(find.byType(CanvasView)).navigation.viewport;
    expect(viewport.visibleWorld.contains(const Offset(3180, 2020)), isFalse);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search in notebook'));
    await tester.pumpAndSettle();
    await typeSearch(tester, 'bulb');
    await tester.tap(find.byTooltip('Next (Enter)'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1'), findsOneWidget);
    expect(viewport.visibleWorld.contains(const Offset(3180, 2020)), isTrue);
  });

  testWidgets('library results follow text that arrives by sync', (tester) async {
    final server = FakeServer();
    SyncApi api(String url, String token) => apiFor(server);
    final other = AppServices.create(AppDatabase.inMemory(), syncApiFactory: api);
    addTearDown(other.dispose);
    final services = AppServices.create(AppDatabase.inMemory(), syncApiFactory: api);
    services.sync.configure(url: 'http://sync.test', token: FakeServer.token);
    await pumpLibrary(tester, services: services);

    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'quantum');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.textContaining('In notebooks'), findsNothing);

    final nb = other.notebooks.create(
      title: 'Lab',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    other.elements.save([
      textBox('q', other.pages.pagesOf(nb.id).single.id, 'Quantum tunnelling', Offset.zero),
    ]);
    await tester.runAsync(() async {
      await other.sync.engine.sync(apiFor(server));
      await services.sync.syncNow();
    });
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('In notebooks · 1 match'), findsOneWidget);
    expect(find.textContaining('tunnelling', findRichText: true), findsOneWidget);
  });

  testWidgets('phone, dark: results and the search bar fit', (tester) async {
    await loadFonts();
    final services = AppServices.create(AppDatabase.inMemory());
    final nbs = seed(services);
    await pumpLibrary(
      tester,
      services: services,
      size: const Size(390, 844),
      themeMode: ThemeMode.dark,
    );
    // Phones: 🔍 opens the field over the title.
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'cell');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(LibraryScreen),
      matchesGoldenFile('goldens/search_library_phone_dark.png'),
    );

    await tester.tap(find.textContaining('mitosis', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsNothing);
    expect(find.text('2/2'), findsOneWidget, reason: 'opened at the tapped match');
    expect(currentPage(tester), 2);
    expect(nbs.biology.title, 'Biology');
    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/search_editor_phone_dark.png'),
    );
    // Phones start with the list folded away, so the page shows.
    expect(find.textContaining('structure', findRichText: true), findsNothing);
    await tester.tap(find.byTooltip('Show results'));
    await tester.pumpAndSettle();
    expect(find.textContaining('structure', findRichText: true), findsOneWidget);
  });

  testWidgets('phone: stepping to a match folds the list and scrolls without panning sideways', (
    tester,
  ) async {
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    final nbs = seed(services);
    await pumpEditorFor(tester, services, nbs.biology, size: const Size(390, 844));
    final doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
    final x = doc.viewport.offset.dx;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await typeSearch(tester, 'cell');
    await tester.tap(find.byTooltip('Show results'));
    await tester.pumpAndSettle();
    final bar = find.byType(EditorSearchBar);
    final search = tester.widget<EditorSearchBar>(bar).controller;
    for (final page in [0, 2, 0]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(currentPage(tester), page);
      expect(doc.viewport.offset.dx, moreOrLessEquals(x), reason: 'no sideways pan');
      final match = search.currentMatch!;
      final t = search.host.transformOf(match.surfaceId)!;
      final top = search.rectsOf(match).first.rect.top * t.scale + t.offset.dy;
      expect(find.byTooltip('Show results'), findsOneWidget, reason: 'the list folded away');
      expect(top, greaterThan(tester.getRect(bar).bottom), reason: 'not under the bar');
    }
  });
}
