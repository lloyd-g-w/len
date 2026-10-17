import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';

import 'content_golden_test.dart' show loadFonts;
import 'content_tools_ui_test.dart' show key, liveStrokes, mouseDrag, openCanvas;

/// Curves in the editor: picked in the Shapes options, drawn anchor by
/// anchor with Enter and Escape, and edited by their handles once
/// selected.
void main() {
  Future<void> tap(WidgetTester tester, Offset at) async {
    await mouseDrag(tester, [at]);
    // Apart, so no tap is the second of a double tap.
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('a curve drawn with the Shape tool: Enter finishes, Escape drops', (tester) async {
    await loadFonts();
    final (services, nb) = await openCanvas(tester);
    await tester.tap(find.byTooltip('Shapes (S)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Shapes (S)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shape-curve')));
    await tester.pumpAndSettle();
    expect(find.text('Tap the first point to close, tap twice to finish'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); // closes the options
    await tester.pumpAndSettle();
    await tap(tester, const Offset(300, 500));
    await mouseDrag(tester, const [Offset(500, 250), Offset(560, 250), Offset(640, 250)]);
    await tester.pump(const Duration(milliseconds: 500));
    await tap(tester, const Offset(800, 500));
    expect(liveStrokes(services, nb.id), isEmpty);
    await key(tester, LogicalKeyboardKey.enter);
    final curve = liveStrokes(services, nb.id).single;
    expect(curve.shape!.kind, ShapeKind.curve);
    expect(curve.shape!.anchorCount, 3);
    // Another, dropped.
    await tap(tester, const Offset(300, 650));
    await tap(tester, const Offset(500, 700));
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(liveStrokes(services, nb.id), hasLength(1));
    // Selected (the lasso, a tap on it), it shows its anchors and tangents.
    await key(tester, LogicalKeyboardKey.keyL);
    final gesture = await tester.startGesture(
      const Offset(500, 250),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/content_curve_handles.png'),
    );
    // Its middle anchor's tangent turned: one undoable edit, still smooth.
    await mouseDrag(tester, const [Offset(640, 250), Offset(660, 270), Offset(640, 320)]);
    await tester.pumpAndSettle();
    final turned = liveStrokes(services, nb.id).single;
    expect(turned.id, isNot(curve.id));
    final p = turned.shape!.points;
    expect(p[4], const Offset(640, 320));
    final into = p[3] - p[2], out = p[4] - p[3];
    expect(
      (into.dx * out.dy - into.dy * out.dx).abs(),
      lessThan(1e-6 * into.distance * out.distance),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(liveStrokes(services, nb.id).single.shape, curve.shape);
  });
}
