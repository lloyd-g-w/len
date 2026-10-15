import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/tabs/open_notebooks.dart';
import 'package:len/ink/render/laser_painter.dart';
import 'package:len/ink/tools/laser.dart';
import 'package:len/ui/app_theme.dart';

import 'support/real_async.dart';

/// Opens [notebook] in the editor with fresh in-memory services.
Future<(AppServices, Notebook)> openCanvas(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  double scale = 1,
  void Function(AppServices services, Notebook notebook)? seed,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = AppServices.create(AppDatabase.inMemory());
  addTearDown(services.dispose);
  // Unmount the editor (which saves settings) before the database closes.
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  final notebook = services.notebooks.create(
    title: 'Board',
    kind: NotebookKind.canvas,
    paper: PaperStyle.blank,
    coverColor: 0xFF3B5BDB,
  );
  seed?.call(services, notebook);
  // World = screen coordinates (at [scale] 1): open at the origin.
  pinCanvasView(services, notebook.id, size, scale: scale);
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
  return (services, notebook);
}

/// Makes canvas [notebookId] open at the origin at [scale] (100 %) on a
/// [size] screen (instead of centred on its content).
void pinCanvasView(AppServices services, String notebookId, Size size, {double scale = 1}) =>
    services.settings.setEditorView(
      notebookId,
      EditorViewState(scale: scale, offset: Offset.zero, size: size).encode(),
    );

/// A horizontal ink stroke from (100, 400) to (200, 400).
Stroke seedStroke(String surface) => Stroke(
  id: 'ink',
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF1F2937,
  width: 3,
  points: [for (var x = 100.0; x <= 200; x += 5) StrokePoint(x, 400, 0.5)],
  createdAt: 1,
);

/// Drags the mouse through [points].
Future<void> mouseDrag(WidgetTester tester, List<Offset> points) async {
  final gesture = await tester.startGesture(points.first, kind: PointerDeviceKind.mouse);
  for (final p in points.skip(1)) {
    await gesture.moveTo(p);
  }
  await gesture.up();
  await tester.pump();
}

List<Stroke> liveStrokes(AppServices s, String surface) => s.strokes.loadChunks(surface, [
  for (var x = -2; x <= 3; x++)
    for (var y = -2; y <= 3; y++) (x: x, y: y),
]);

List<SurfaceElement> liveElements(AppServices s, String surface) => s.elements.loadChunks(surface, [
  for (var x = -2; x <= 3; x++)
    for (var y = -2; y <= 3; y++) (x: x, y: y),
]);

Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  testWidgets('lasso: select, move, then undo restores the stroke', (tester) async {
    final (services, nb) = await openCanvas(
      tester,
      seed: (s, nb) => s.strokes.save([seedStroke(nb.id)]),
    );
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [
      Offset(80, 350),
      Offset(260, 350),
      Offset(260, 450),
      Offset(80, 450),
      Offset(80, 360),
    ]);
    expect(find.byTooltip('Delete (Del)'), findsOneWidget); // the context menu

    await mouseDrag(tester, const [Offset(150, 400), Offset(200, 420), Offset(250, 450)]);
    final moved = liveStrokes(services, nb.id).single;
    expect(moved.points.first.offset, const Offset(200, 450));

    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pump();
    final restored = liveStrokes(services, nb.id).single;
    expect(restored.id, 'ink');
    expect(find.byTooltip('Delete (Del)'), findsNothing); // selection dropped
  });

  testWidgets('lasso: tap selects, the menu deletes, Ctrl+V pastes it back', (tester) async {
    final (services, nb) = await openCanvas(
      tester,
      seed: (s, nb) => s.strokes.save([seedStroke(nb.id)]),
    );
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [Offset(150, 401)]);
    await tester.tap(find.byTooltip('Cut (Ctrl+X)'));
    await tester.pump();
    expect(liveStrokes(services, nb.id), isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    // Waits for the cut's own clipboard write (its picture renders for
    // real), then checks the system clipboard for an image and text.
    await pumpUntil(tester, () => liveStrokes(services, nb.id).isNotEmpty);
    final pasted = liveStrokes(services, nb.id).single;
    expect(pasted.id, isNot('ink'));
    expect(pasted.points.first.offset.dx, closeTo(640 - 50, 1e-3)); // centred on screen
  });

  testWidgets('text: tap to create, type, finish; undo removes it', (tester) async {
    final (services, nb) = await openCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(300, 400)]);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('text-box-field'));
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Hello\nworld');
    await tester.tap(find.byTooltip('Lists and headings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bulleted list'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Done (Esc)'));
    await tester.pumpAndSettle();

    final element = liveElements(services, nb.id).single;
    final data = TextData.fromJson(element.data);
    expect(data.text, 'Hello\nworld');
    expect(data.paras.last.list, ListKind.bullet);
    expect(element.rect.left, 300);
    expect(find.byKey(const ValueKey('text-box-field')), findsNothing);

    // Tapping the box with the text tool edits it again.
    await mouseDrag(tester, [element.rect.center]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('text-box-field')), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pump();
    expect(liveElements(services, nb.id), isEmpty);
  });

  testWidgets('typing in a text box does not trigger tool shortcuts', (tester) async {
    await openCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(300, 400)]);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(find.byKey(const ValueKey('text-box-field')), findsOneWidget);
  });

  testWidgets('shape tool draws a rectangle stroke by dragging', (tester) async {
    final (services, nb) = await openCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyS);
    await mouseDrag(tester, const [Offset(300, 300), Offset(400, 350), Offset(500, 420)]);
    final stroke = liveStrokes(services, nb.id).single;
    final xs = stroke.points.map((p) => p.x);
    final ys = stroke.points.map((p) => p.y);
    expect(xs.reduce((a, b) => a < b ? a : b), 300);
    expect(xs.reduce((a, b) => a > b ? a : b), 500);
    expect(ys.reduce((a, b) => a > b ? a : b), 420);
    expect(stroke.style.streamline, 0);
  });

  testWidgets('laser pointer leaves no ink and fades away', (tester) async {
    final (services, nb) = await openCanvas(tester);
    LaserTrail trail() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<LaserPainter>()
        .single
        .trail;
    await key(tester, LogicalKeyboardKey.keyK);
    await mouseDrag(tester, const [Offset(300, 300), Offset(400, 350), Offset(500, 420)]);
    expect(liveStrokes(services, nb.id), isEmpty);
    expect(trail().isEmpty, isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(LaserConfig.defaultDuration);
    await tester.pump(const Duration(milliseconds: 100));
    expect(trail().isVisible, isFalse);
  });

  testWidgets('with a mouse, the laser dot follows the pointer without a press', (tester) async {
    await openCanvas(tester);
    LaserTrail trail() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<LaserPainter>()
        .single
        .trail;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(300, 300));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(const Offset(320, 300));
    await tester.pump();
    expect(trail().head, isNull, reason: 'not with the pen');

    await key(tester, LogicalKeyboardKey.keyK);
    await mouse.moveTo(const Offset(400, 350));
    await tester.pump();
    expect(trail().head, const Offset(400, 350)); // World = screen here.
    expect(trail().headAlpha, 1);
    expect(trail().isEmpty, isTrue);

    // Another tool: the dot goes.
    await key(tester, LogicalKeyboardKey.keyP);
    await tester.pump(const Duration(seconds: 3));
    expect(trail().isVisible, isFalse);
  });

  testWidgets('the toolbar shape picker selects the shape tool', (tester) async {
    await openCanvas(tester);
    await tester.tap(find.byTooltip('Shapes (S)'));
    await tester.pump();
    await tester.tap(find.byTooltip('Shapes (S)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shape-ellipse')));
    await tester.pumpAndSettle();
    final button = tester.widget<IconButton>(
      find.ancestor(of: find.byTooltip('Shapes (S)'), matching: find.byType(IconButton)),
    );
    expect(button.isSelected, isTrue);
  });
}
