import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/render/live_stroke.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_renderer.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/shapes/polyline.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/content_tools.dart';
import 'package:len/ink/viewport.dart';

import 'document_editor_test.dart' show pumpEditor;

/// The Shape tool driven through the input controller as the editor drives
/// it: every kind, with a mouse, a pen and a finger, at several zooms.
void main() {
  late AppDatabase db;
  late SurfaceModel model;
  late ViewportController viewport;
  late ToolSettings tools;
  late LiveInk live;
  late ContentTools content;
  late InkInputController input;

  setUp(() {
    db = AppDatabase.inMemory();
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
    );
    viewport = ViewportController()..setSize(const Size(800, 600));
    // Fingers draw too.
    tools = ToolSettings(stylusOnly: false)..tool = EditorTool.shape;
    live = LiveInk();
    content = ContentTools(
      model: model,
      viewport: viewport,
      tools: tools,
      live: live,
      clipboard: InkClipboard(),
    );
    input = InkInputController(
      model: model,
      viewport: viewport,
      tools: tools,
      live: live,
      content: content,
    );
  });

  tearDown(() {
    content.dispose();
    model.dispose();
    db.close();
  });

  /// The outline the live layer paints now, and the one it would paint for
  /// [shape] from scratch: the same when the preview is right.
  void expectPreview(ShapeGeometry shape, String reason) {
    final shown = LiveStrokeBuilder.livePath(live).combined.getBounds();
    final spec = StrokeRenderer.specFor(live.tool, live.width, live.style);
    final fresh = StrokeOutline.build(
      ShapeBuilder.pointsOf(shape, spacing: 2 / viewport.scale),
      spec,
      complete: false,
    ).getBounds();
    expect(live.shape, shape, reason: reason);
    expect((shown.topLeft - fresh.topLeft).distance, lessThan(0.5), reason: reason);
    expect((shown.bottomRight - fresh.bottomRight).distance, lessThan(0.5), reason: reason);
  }

  for (final scale in [0.5, 1.0, 2.5]) {
    for (final kind in [
      PointerDeviceKind.mouse,
      PointerDeviceKind.stylus,
      PointerDeviceKind.touch,
    ]) {
      test('every shape at ${scale}x with a ${kind.name}: live preview, then exactly that', () {
        viewport.setView(scale: scale, offset: const Offset(30, -20));
        var pointer = 1;
        for (final shapeKind in ShapeKind.drawable) {
          tools.shape = shapeKind;
          final id = pointer++;
          const from = Offset(200, 150);
          input.handleDown(PointerDownEvent(pointer: id, kind: kind, position: from));
          final start = viewport.toWorld(from);
          // Out, back in and out again: the preview always spans start → pointer.
          for (final to in const [
            Offset(260, 190),
            Offset(420, 330),
            Offset(300, 240),
            Offset(460, 380),
          ]) {
            input.handleMove(PointerMoveEvent(pointer: id, kind: kind, position: to));
            final expected = ShapeBuilder.dragged(shapeKind, start, viewport.toWorld(to));
            expectPreview(expected, '$shapeKind at $to');
          }
          input.handleUp(PointerUpEvent(pointer: id, kind: kind, position: const Offset(460, 380)));
          final stroke = model.history.takeUndo()!.added.single;
          final expected = ShapeBuilder.dragged(
            shapeKind,
            start,
            viewport.toWorld(const Offset(460, 380)),
          );
          expect(stroke.shape, expected, reason: '$shapeKind');
          expect(
            stroke.points,
            ShapeBuilder.pointsOf(expected, spacing: 2 / scale),
            reason: '$shapeKind',
          );
          expect(stroke.style.unit, 1 / scale);
          expect(live.isDrawing, isFalse);
        }
      });
    }
  }

  test('a shape is an even line with round ends, whatever the pen', () {
    tools.updateConfig(
      InkTool.ballpoint,
      (c) => c.copyWith(ends: const PenEnds(style: StrokeEnds.tapered, taperLength: 8)),
    );
    tools.shape = ShapeKind.rectangle;
    const k = PointerDeviceKind.stylus;
    input
      ..handleDown(const PointerDownEvent(pointer: 1, kind: k, position: Offset(100, 100)))
      ..handleMove(const PointerMoveEvent(pointer: 1, kind: k, position: Offset(300, 200)))
      ..handleUp(const PointerUpEvent(pointer: 1, kind: k, position: Offset(300, 200)));
    final style = model.history.takeUndo()!.added.single.style;
    expect(style.ends, StrokeEnds.round);
    expect(style.taperStart + style.taperEnd, 0);
    expect(style.thinning, 0);
    expect(style.streamline, 0);
  });

  testWidgets('Shift pressed or released mid-drag reshapes the preview at once', (tester) async {
    tools.shape = ShapeKind.rectangle;
    const k = PointerDeviceKind.mouse;
    input
      ..handleDown(const PointerDownEvent(pointer: 1, kind: k, position: Offset(100, 100)))
      ..handleMove(const PointerMoveEvent(pointer: 1, kind: k, position: Offset(300, 160)));
    expect(
      live.shape,
      ShapeBuilder.dragged(ShapeKind.rectangle, const Offset(100, 100), const Offset(300, 160)),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final square = ShapeBuilder.dragged(
      ShapeKind.rectangle,
      const Offset(100, 100),
      const Offset(300, 300),
    );
    expect(live.shape, square);
    expectPreview(square, 'square');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(
      live.shape,
      ShapeBuilder.dragged(ShapeKind.rectangle, const Offset(100, 100), const Offset(300, 160)),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    input.handleUp(const PointerUpEvent(pointer: 1, kind: k, position: Offset(300, 160)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    // What was shown is what is committed.
    expect(model.history.takeUndo()!.added.single.shape, square);
  });

  test('a drag shorter than the slop draws nothing; a tap on a shape selects it', () {
    tools.shape = ShapeKind.ellipse;
    const k = PointerDeviceKind.stylus;
    input
      ..handleDown(const PointerDownEvent(pointer: 1, kind: k, position: Offset(100, 100)))
      ..handleMove(const PointerMoveEvent(pointer: 1, kind: k, position: Offset(102, 101)))
      ..handleUp(const PointerUpEvent(pointer: 1, kind: k, position: Offset(102, 101)));
    expect(model.history.canUndo, isFalse);
    input
      ..handleDown(const PointerDownEvent(pointer: 2, kind: k, position: Offset(100, 100)))
      ..handleMove(const PointerMoveEvent(pointer: 2, kind: k, position: Offset(300, 200)))
      ..handleUp(const PointerUpEvent(pointer: 2, kind: k, position: Offset(300, 200)));
    final ellipse = model.strokesNear(const Rect.fromLTWH(0, 0, 400, 400)).single;
    // A tap on its outline (the left end) selects it, still with the Shape tool.
    input
      ..handleDown(const PointerDownEvent(pointer: 3, kind: k, position: Offset(100, 150)))
      ..handleUp(const PointerUpEvent(pointer: 3, kind: k, position: Offset(100, 150)));
    expect(content.selection.strokes.single.id, ellipse.id);
    expect(tools.tool, EditorTool.shape);
  });

  testWidgets('on a page of a notebook, in the editor, with the pen', (tester) async {
    final (services, nb) = await pumpEditor(tester, size: const Size(1000, 1300));
    final page = services.pages.pagesOf(nb.id).first;
    var i = 0;
    for (final kind in ShapeKind.drawable) {
      // Pick it in the Shapes options (the second tap on the tool opens them).
      if (find.byKey(ValueKey('shape-${kind.name}')).evaluate().isEmpty) {
        await tester.tap(find.byTooltip('Shapes (S)'));
        await tester.pumpAndSettle();
      }
      if (find.byKey(ValueKey('shape-${kind.name}')).evaluate().isEmpty) {
        await tester.tap(find.byTooltip('Shapes (S)'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(ValueKey('shape-${kind.name}')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final a = Offset(180.0 + 160 * (i % 4), 420.0 + 260 * (i ~/ 4));
      final g = await tester.startGesture(a, kind: PointerDeviceKind.stylus);
      for (var k = 1; k <= 10; k++) {
        await g.moveTo(a + const Offset(120, 180) * (k / 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pump();
      i++;
    }
    final shapes = services.strokes
        .loadChunks(page.id, [
          for (var x = -1; x <= 2; x++)
            for (var y = -1; y <= 2; y++) (x: x, y: y),
        ])
        .where((s) => s.shape != null)
        .toList();
    expect(shapes.map((s) => s.shape!.kind).toSet(), ShapeKind.drawable.toSet());
    final sizes = {for (final s in shapes) Polyline.bounds(ShapeBuilder.outline(s.shape!)).size};
    // All dragged alike: one size on the page (whatever its zoom), the outline their points.
    expect(sizes.map((s) => (s.width / s.height * 100).round()).toSet(), {67});
    for (final s in shapes) {
      // (Points are stored as float32.)
      expect(
        (s.points.first.offset - ShapeBuilder.outline(s.shape!).first).distance,
        lessThan(1e-3),
      );
    }
  });
}
