import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/stroke_style.dart';
import 'package:len/features/editor/canvas/canvas_view.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/eyedropper/eyedropper_layer.dart';
import 'package:len/features/editor/pen/ink_slots.dart';
import 'package:len/ink/shapes/shape_fill.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/color_picker/color_choices.dart';

import 'support/tester_clock.dart';

const _fill = 0xFFFFD43B;
const _outline = 0xFF1C7ED6;
const _ink = 0xFFE03131;

/// A yellow square with a blue outline at (100, 100)–(300, 300) of the
/// surface, and a red line across it at y = 200.
List<Stroke> _content(String surface) => [
  Stroke(
    id: 'square',
    surfaceId: surface,
    tool: InkTool.ballpoint,
    color: _outline,
    width: 4,
    style: const StrokeStyle(fill: _fill),
    points: [
      for (final (x, y) in [(100.0, 100.0), (300.0, 100.0), (300.0, 300.0), (100.0, 300.0)])
        StrokePoint(x, y, 0.5),
      const StrokePoint(100, 100, 0.5),
    ],
    createdAt: 1,
  ),
  Stroke(
    id: 'line',
    surfaceId: surface,
    tool: InkTool.ballpoint,
    color: _ink,
    width: 6,
    points: const [StrokePoint(80, 200, 0.5), StrokePoint(320, 200, 0.5)],
    createdAt: 2,
  ),
];

/// Opens an editor of a notebook ([canvas] or one page of [paper]) with
/// [_content]; returns its tools and how to put a surface point on screen.
Future<(ToolSettings, Offset Function(Offset))> _open(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  bool canvas = false,
  PaperColor paper = PaperColor.white,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = AppServices.create(AppDatabase.inMemory(), clock: const TesterClock());
  addTearDown(services.dispose);
  final nb = services.notebooks.create(
    title: 'Colours',
    kind: canvas ? NotebookKind.canvas : NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0,
    paperColor: paper,
    firstPage: PageTemplate(color: paper),
  );
  final surface = canvas ? nb.id : services.pages.pagesOf(nb.id).single.id;
  services.strokes.save(_content(surface));
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: EditorScreen(notebook: nb),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final tools = tester.widget<ColorSlots>(find.byType(ColorSlots).first).tools;
  Offset toScreen(Offset p) {
    if (canvas) {
      final view = tester.widget<CanvasView>(find.byType(CanvasView));
      return view.navigation.viewport.toScreen(p);
    }
    final doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
    return doc.viewport.toScreen(p + doc.layout.frameOf(0)!.topLeft);
  }

  return (tools, toScreen);
}

/// Opens the first quick colour's editor and starts the eyedropper.
Future<void> _pickFromSlot(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('color-0')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('color-slot-editor')), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('pick-from-page')));
  await tester.pumpAndSettle();
}

Finder get _hint => find.text(EyedropperLayer.hint);

/// The colour slot editor, shown or stepped aside.
Finder get _slotEditor => find.byKey(const ValueKey('color-slot-editor'), skipOffstage: false);

void main() {
  int slot(ToolSettings tools) => tools.configOf(InkTool.ballpoint).colors[0];

  testWidgets('pick from page: the picker steps aside, a hint shows, a tap takes the colour of '
      'the content there, which becomes a recent colour', (tester) async {
    final (tools, toScreen) = await _open(tester);
    final before = slot(tools);
    await _pickFromSlot(tester);
    expect(_hint, findsOneWidget);
    expect(find.byKey(const ValueKey('color-slot-editor')), findsNothing, reason: 'offstage');
    expect(_slotEditor, findsOneWidget, reason: 'kept, to take the colour');

    // Pressing shows the loupe; lifting picks.
    final gesture = await tester.startGesture(toScreen(const Offset(200, 150)));
    await tester.pump();
    expect(find.byKey(const ValueKey('eyedropper-loupe')), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(slot(tools), _fill);
    expect(slot(tools), isNot(before));
    expect(tools.recentColors.first, _fill);
    expect(_hint, findsNothing);
    expect(_slotEditor, findsNothing, reason: 'the picker closed');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stroke gives its own colour; bare paper the paper colour', (tester) async {
    final (tools, toScreen) = await _open(tester, paper: PaperColor.dark);
    await _pickFromSlot(tester);
    await tester.tapAt(toScreen(const Offset(250, 200)), kind: PointerDeviceKind.stylus);
    await tester.pumpAndSettle();
    expect(slot(tools), _ink);
    await _pickFromSlot(tester);
    await tester.tapAt(toScreen(const Offset(400, 400)), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(slot(tools), PaperColor.dark.paper.toARGB32());
    expect(tools.recentColors.take(2), [PaperColor.dark.paper.toARGB32(), _ink]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape cancels: nothing changes, the picker closes', (tester) async {
    final (tools, _) = await _open(tester);
    final before = slot(tools);
    await _pickFromSlot(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_hint, findsNothing);
    expect(_slotEditor, findsNothing);
    expect(slot(tools), before);
    expect(tools.recentColors, isEmpty);
    // The editor's shortcuts work again.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    expect(tools.tool, EditorTool.highlighter);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap on the chrome cancels, and does nothing else', (tester) async {
    final (tools, _) = await _open(tester);
    final before = slot(tools);
    await _pickFromSlot(tester);
    await tester.tap(find.byTooltip('Highlighter (H)'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(_hint, findsNothing);
    expect(_slotEditor, findsNothing);
    expect(tools.tool, EditorTool.pen, reason: 'the tap only cancelled');
    expect(slot(tools), before);
    expect(tools.recentColors, isEmpty);
    // The page still draws afterwards.
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shape fill picks its solid colour from the page', (tester) async {
    final (tools, toScreen) = await _open(tester);
    await tester.tap(find.byTooltip('Shapes (S)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Shapes (S)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fill-Solid colour')));
    await tester.pumpAndSettle();
    final droppers = find.byKey(const ValueKey('pick-from-page'));
    await tester.ensureVisible(droppers.last);
    await tester.tap(droppers.last);
    await tester.pumpAndSettle();
    expect(_hint, findsOneWidget);
    await tester.tapAt(toScreen(const Offset(250, 200)));
    await tester.pumpAndSettle();
    expect(tools.shapeFill, const ShapeFill.solid(_ink));
    expect(tools.recentColors.first, _ink);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phones: the sheet steps aside the same way', (tester) async {
    final (tools, toScreen) = await _open(tester, size: const Size(390, 844));
    await _pickFromSlot(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(_hint, findsOneWidget);
    await tester.tapAt(toScreen(const Offset(150, 150)));
    await tester.pumpAndSettle();
    expect(slot(tools), _fill);
    expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('infinite canvases pick the same way', (tester) async {
    final (tools, toScreen) = await _open(tester, canvas: true);
    await _pickFromSlot(tester);
    await tester.tapAt(toScreen(const Offset(102, 250)));
    await tester.pumpAndSettle();
    expect(slot(tools), _outline);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pickers outside the editor offer no eyedropper', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ColorChoices(color: _ink, onChanged: (_) {}),
        ),
      ),
    );
    expect(find.text('Custom'), findsOneWidget);
    expect(find.byKey(const ValueKey('pick-from-page')), findsNothing);
  });
}
