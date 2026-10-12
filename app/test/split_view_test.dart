import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/audio/backends/audio_backends.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/editor_toolbar.dart';
import 'package:len/features/editor/split/split_view.dart';
import 'package:len/features/editor/tabs/editor_workspace.dart';
import 'package:len/features/editor/tabs/open_notebooks.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/app_theme.dart';

import 'document_editor_test.dart' show closeEditor, drawAt, pumpEditor;
import 'editor_tabs_test.dart' show notebook;

/// A desktop workspace with two notebooks open: "Physics" (active) and
/// "Chemistry", both paged unless [kind] says otherwise.
Future<(AppServices, Notebook, Notebook)> pumpWorkspace(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  NotebookKind kind = NotebookKind.paged,
  AudioBackends? audio,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = AppServices.create(AppDatabase.inMemory(), audio: audio);
  addTearDown(s.dispose);
  Notebook make(String title) =>
      s.notebooks.create(title: title, kind: kind, paper: PaperStyle.collegeRuled, coverColor: 0);
  final physics = make('Physics'), chemistry = make('Chemistry');
  s.openNotebooks
    ..open(chemistry)
    ..open(physics);
  await tester.pumpWidget(
    AppScope(
      services: s,
      child: MaterialApp(
        theme: AppTheme.light(),
        navigatorObservers: [s.routeOwners],
        home: const EditorWorkspace(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (s, physics, chemistry);
}

List<Stroke> inkOfNotebook(AppServices s, Notebook n) =>
    SurfaceCopier(s.strokes).loadAll(s.pages.pagesOf(n.id).first.id);

Finder paneOf(int index) => find.byType(PagedDocumentView).at(index);

Future<void> drawIn(WidgetTester tester, int pane, {Offset at = const Offset(-100, 0)}) =>
    drawAt(tester, tester.getCenter(paneOf(pane)) + at);

void main() {
  group('OpenNotebooks split', () {
    test('opens, swaps, and closes with its tab', () {
      final tabs = OpenNotebooks();
      addTearDown(tabs.dispose);
      tabs
        ..open(notebook('a'))
        ..open(notebook('b'))
        ..openSplit('a');
      expect((tabs.activeId, tabs.splitId), ('b', 'a'));
      tabs.swapSplit();
      expect((tabs.activeId, tabs.splitId), ('a', 'b'));
      tabs.splitFraction = 0.95;
      expect(tabs.splitFraction, 0.75);
      tabs.close('b');
      expect(tabs.splitId, isNull);
      tabs.openSplit('missing');
      expect(tabs.splitId, isNull);
    });
  });

  test('closing the active tab next to the split tab moves it to the first pane', () {
    final tabs = OpenNotebooks();
    addTearDown(tabs.dispose);
    tabs
      ..open(notebook('a'))
      ..open(notebook('b'))
      ..openSplit('a');
    tabs.splitView = const EditorViewState(scale: 2, offset: Offset(5, 6));
    tabs.close('b');
    expect((tabs.activeId, tabs.splitId), ('a', null));
    expect(tabs.viewOf('a')?.scale, 2, reason: 'where the second pane was looking');
  });

  test('the tab limit never closes the tab shown in the second pane', () {
    final tabs = OpenNotebooks(maxTabs: 3);
    addTearDown(tabs.dispose);
    tabs
      ..open(notebook('a'))
      ..open(notebook('b'))
      ..openSplit('a')
      ..open(notebook('c'))
      ..open(notebook('d'));
    expect(tabs.splitId, 'a');
    expect(tabs.tabs.map((t) => t.id), unorderedEquals(['a', 'c', 'd']));
  });

  test('split view fits tablets in landscape and desktops only', () {
    expect(SplitView.fits(const Size(1440, 900)), isTrue);
    expect(SplitView.fits(const Size(1280, 800)), isTrue);
    expect(SplitView.fits(const Size(800, 1280)), isFalse); // Portrait tablet.
    expect(SplitView.fits(const Size(844, 390)), isFalse); // Phone, landscape.
    expect(SplitView.fits(const Size(390, 844)), isFalse);
  });

  testWidgets('open a second notebook beside, resize, drag a selection across, close', (
    tester,
  ) async {
    final (s, physics, chemistry) = await pumpWorkspace(tester);
    final firstEditor = tester.state(find.byType(EditorScreen));
    await tester.tap(find.byTooltip('Open in split view'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chemistry').last); // The menu's, not the tab's.
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNWidgets(2));
    // The first editor was kept, not rebuilt.
    expect(tester.state(find.byType(EditorScreen).first), same(firstEditor));
    expect(find.byTooltip('Close this pane'), findsOneWidget);
    expect(tester.getCenter(paneOf(0)).dx, lessThan(720));
    expect(tester.getCenter(paneOf(1)).dx, greaterThan(720));

    // Drag the divider: the first pane widens.
    final divider = find.byTooltip('Drag to resize · double-tap for halves');
    final before = tester.getSize(paneOf(0)).width;
    await tester.drag(divider, const Offset(120, 0));
    await tester.pumpAndSettle();
    // (Less the drag's start slop.)
    expect(tester.getSize(paneOf(0)).width, inInclusiveRange(before + 90, before + 120));

    // Each pane edits its own notebook.
    await drawIn(tester, 0);
    await drawIn(tester, 1);
    expect(inkOfNotebook(s, physics), hasLength(1));
    expect(inkOfNotebook(s, chemistry), hasLength(1));

    // Select the first pane's ink and drag it into the second: a copy.
    final ink = inkOfNotebook(s, physics).single;
    final left = tester.getCenter(paneOf(0)) + const Offset(-100, 0);
    await tester.tapAt(left, buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all on page'));
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(
      left + const Offset(30, 10),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 1; i <= 20; i++) {
      await drag.moveTo(left + Offset(30 + i * 40.0, 10));
      await tester.pump();
    }
    expect(find.text('Drop to copy here'), findsOneWidget);
    await drag.up();
    await tester.pumpAndSettle();
    expect(inkOfNotebook(s, chemistry), hasLength(2));
    // The original stayed where it was.
    expect(inkOfNotebook(s, physics).single.points.first, ink.points.first);

    // Close the second pane.
    await tester.tap(find.byTooltip('Close this pane'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);
    expect(s.openNotebooks.splitId, isNull);
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });

  testWidgets('the same notebook twice: edits show in both; tools are linked', (tester) async {
    final (s, physics, _) = await pumpWorkspace(tester);
    s.openNotebooks.openSplit(physics.id);
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNWidgets(2));

    int strokesIn(int pane) {
      final doc = tester.widget<PagedDocumentView>(paneOf(pane)).controller;
      return doc.surfaces.surfaceOf(doc.pages.first.id).model.strokesNear(Rect.largest).length;
    }

    await drawIn(tester, 0);
    expect(strokesIn(0), 1);
    await tester.pump(const Duration(milliseconds: 300)); // The mirror delay.
    expect(strokesIn(1), 1);
    // Undo shows in the other view too.
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(strokesIn(0), 0);
    expect(strokesIn(1), 0);

    // Both panes use the same tools.
    ToolSettings toolsOf(int i) =>
        tester.widgetList<EditorToolbar>(find.byType(EditorToolbar)).elementAt(i).tools;
    toolsOf(0).tool = EditorTool.highlighter;
    await tester.pump();
    expect(toolsOf(1).tool, EditorTool.highlighter);
    toolsOf(1).selectColor(2);
    await tester.pump();
    expect(toolsOf(0).activeConfig.colorIndex, 2);
    s.openNotebooks.closeSplit();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });

  testWidgets('phones and portrait tablets show one pane, no split button', (tester) async {
    final (s, physics, _) = await pumpWorkspace(tester, size: const Size(800, 1280));
    expect(find.byTooltip('Open in split view'), findsNothing);
    s.openNotebooks.openSplit(physics.id);
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);
    // Rotated to landscape: the split appears.
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });

  testWidgets('tab menu: open in split view', (tester) async {
    final (s, _, chemistry) = await pumpWorkspace(tester);
    await tester.tap(
      find.byKey(ValueKey('tab-${chemistry.id}')),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in split view'));
    await tester.pumpAndSettle();
    expect(s.openNotebooks.splitId, chemistry.id);
    expect(find.byType(EditorScreen), findsNWidgets(2));
    await closeEditor(tester);
  });

  testWidgets('swapping panes keeps where each notebook was looking', (tester) async {
    final (s, physics, chemistry) = await pumpWorkspace(tester);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    PagedDocumentView view(int pane) => tester.widget<PagedDocumentView>(paneOf(pane));
    final second = view(1).controller.viewport;
    second.zoomAt(tester.getCenter(paneOf(1)), 1.5);
    await tester.pump();
    final (left, right) = (view(0).controller.viewport.scale, second.scale);
    expect(right, isNot(closeTo(left, 1e-3)));
    s.openNotebooks.swapSplit();
    await tester.pumpAndSettle();
    expect((s.openNotebooks.activeId, s.openNotebooks.splitId), (chemistry.id, physics.id));
    expect(view(0).controller.viewport.scale, closeTo(right, 1e-6));
    expect(view(1).controller.viewport.scale, closeTo(left, 1e-6));
    await closeEditor(tester);
  });

  testWidgets('the second pane in focus mode, then closed: the first pane shows again', (
    tester,
  ) async {
    final (s, _, chemistry) = await pumpWorkspace(tester);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More options').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Focus mode'));
    await tester.pumpAndSettle();
    expect(paneOf(0), findsOneWidget, reason: 'only the pane in focus mode is shown');
    s.openNotebooks.closeSplit();
    await tester.pumpAndSettle();
    expect(paneOf(0), findsOneWidget);
    expect(find.byTooltip('Undo (Ctrl+Z)'), findsOneWidget, reason: 'with its chrome');
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });

  testWidgets('F5: focus mode with the laser; Space turns pages; Esc restores', (tester) async {
    final (s, _) = await pumpEditor(tester, size: const Size(1280, 900));
    final tools = tester.widget<EditorToolbar>(find.byType(EditorToolbar)).tools;
    final doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
    bool chrome() => find.byTooltip('Undo (Ctrl+Z)').hitTestable().evaluate().isNotEmpty;
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(chrome(), isFalse);
    expect(tools.tool, EditorTool.laser);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(doc.currentPage, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(doc.currentPage, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(chrome(), isTrue);
    expect(tools.tool, EditorTool.pen);
    // F5 again enters and leaves it; F11 focus mode keeps the tool.
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(tools.tool, EditorTool.laser);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(tools.tool, EditorTool.pen);
    expect(chrome(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(chrome(), isFalse);
    expect(tools.tool, EditorTool.pen);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(chrome(), isTrue);
    expect(s.settings.pageFlow, isNull);
    await closeEditor(tester);
  });

  testWidgets('finger double tap zooms in about the tap and back to the page fit', (tester) async {
    final (s, _) = await pumpEditor(tester, size: const Size(1280, 900));
    s.preferences.stylusOnly = true; // Fingers navigate.
    await tester.pump();
    final doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
    final fit = doc.viewport.scale;
    Future<void> doubleTap(Offset at) async {
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(at);
      await tester.pumpAndSettle();
    }

    const at = Offset(500, 500);
    final world = doc.viewport.toWorld(at);
    await doubleTap(at);
    expect(doc.viewport.scale, closeTo(fit * 2, 1e-6));
    expect((doc.viewport.toScreen(world) - at).distance, lessThan(1));
    await doubleTap(at);
    expect(doc.viewport.scale, closeTo(fit, 1e-6));
    // Mouse double clicks don't zoom (and drawing fingers don't either).
    await closeEditor(tester);
    expect(find.byType(EditorScreen), findsNothing);
  });
}
