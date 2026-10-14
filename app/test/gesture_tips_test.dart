import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/chrome/editor_tips.dart';
import 'package:len/features/editor/editor_toolbar.dart';
import 'package:len/ink/input/hold_to_straighten.dart';

import 'document_editor_test.dart' show closeEditor, pumpEditor;

/// R8-26: hold to snap and scribble to erase live in Settings → Writing and
/// are taught once each, at a calm moment (the budget: tip_budget_test).
void main() {
  group('what counts as a line or shape drawn by hand', () {
    List<Offset> line(Offset a, Offset b, {double wobble = 0}) {
      final n = ((b - a).distance / 4).ceil();
      return [
        for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)! + Offset(0, i.isEven ? wobble : 0),
      ];
    }

    test('a long, nearly straight line, or a closed shape', () {
      expect(
        HoldToStraighten.wouldSnap(line(Offset.zero, const Offset(200, 6), wobble: 2), 1),
        true,
      );
      expect(
        HoldToStraighten.wouldSnap([
          ...line(Offset.zero, const Offset(100, 0)),
          ...line(const Offset(100, 0), const Offset(100, 60)),
          ...line(const Offset(100, 60), const Offset(0, 60)),
          ...line(const Offset(0, 60), const Offset(0, 2)),
        ], 1),
        isTrue,
        reason: 'a box',
      );
    });

    test('but not a short line, a wavy one or writing', () {
      expect(HoldToStraighten.wouldSnap(line(Offset.zero, const Offset(80, 0)), 1), isFalse);
      expect(
        HoldToStraighten.wouldSnap(line(Offset.zero, const Offset(80, 0)), 2),
        isTrue,
        reason: 'zoomed in, it is long on screen',
      );
      expect(
        HoldToStraighten.wouldSnap([
          for (var i = 0; i <= 100; i++) Offset(i * 2.0, 12 * math.sin(i / 5)),
        ], 1),
        isFalse,
      );
      // Cursive-like loops moving along a line.
      expect(
        HoldToStraighten.wouldSnap([
          for (var i = 0; i <= 200; i++)
            Offset(i * 1.0 + 8 * math.cos(i / 4), 10 * math.sin(i / 4)),
        ], 1),
        isFalse,
      );
    });
  });

  testWidgets('in the editor: Settings → Writing drives the pen; a ruled line teaches the hold', (
    tester,
  ) async {
    final (s, _) = await pumpEditor(tester, size: const Size(1280, 900));
    s.preferences.stylusOnly = true;
    s.settings.markTipSeen(EditorTip.penButton.name); // Not this one.
    await tester.pump();
    final tools = tester.widget<EditorToolbar>(find.byType(EditorToolbar)).tools;
    s.preferences.scribbleToErase = false;
    s.preferences.holdToSnap = false;
    await tester.pump();
    expect(tools.scribbleToErase, isFalse);
    expect(tools.holdToStraighten, isFalse);
    s.preferences.holdToSnap = true;
    await tester.pump();
    expect(tools.holdToStraighten, isTrue);

    // A long straight line, drawn quickly and lifted: after a calm moment,
    // the tip.
    final pen = await tester.startGesture(const Offset(300, 400), kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 30; i++) {
      await pen.moveTo(Offset(300 + i * 10.0, 400 + (i.isEven ? 1 : 0)));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await pen.up();
    await tester.pump();
    const tip = 'Hold the pen still at the end of a line or shape to snap it clean';
    expect(find.text(tip), findsNothing, reason: 'not at once');
    await tester.pump(TipsController.calmFor);
    await tester.pumpAndSettle();
    expect(find.text(tip), findsOneWidget);
    await tester.pump(TipsController.visibleFor);
    await tester.pumpAndSettle();
    await closeEditor(tester);
  });
}
