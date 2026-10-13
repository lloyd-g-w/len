import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/features/editor/chrome/toolbar_slot.dart';
import 'package:len/features/editor/editor_screen.dart';

import 'document_editor_test.dart' show closeEditor, pumpEditor;

void main() {
  group('snapping', () {
    const free = Size(1000, 600);

    test('within 48 px of an edge, the palette goes to its middle', () {
      expect(ToolbarSlot.snap((0.03, 0.2), free), (0.0, 0.5)); // 30 px from the left
      expect(ToolbarSlot.snap((0.98, 0.7), free), (1.0, 0.5)); // 20 px from the right
      expect(ToolbarSlot.snap((0.3, 0.05), free), (0.5, 0.0)); // 30 px from the top
      expect(ToolbarSlot.snap((0.7, 0.95), free), (0.5, 1.0)); // 30 px from the bottom
    });

    test('elsewhere it stays put; in a corner the nearer edge wins', () {
      expect(ToolbarSlot.snap((0.4, 0.4), free), (0.4, 0.4));
      expect(ToolbarSlot.snap((0.06, 0.4), free), (0.06, 0.4)); // 60 px: too far
      expect(ToolbarSlot.snap((0.01, 0.06), free), (0.0, 0.5)); // 10 px left, 36 px top
      expect(ToolbarSlot.snap((0.04, 0.01), free), (0.5, 0.0)); // 40 px left, 6 px top
    });

    test('only the side edges run down', () {
      expect(ToolbarSlot.isVertical((0, 0.5)), isTrue);
      expect(ToolbarSlot.isVertical((1, 0.5)), isTrue);
      expect(ToolbarSlot.isVertical((0.5, 1)), isFalse);
      expect(ToolbarSlot.isVertical(null), isFalse);
    });
  });

  testWidgets('dragged to the left edge, the palette snaps and runs down', (tester) async {
    final (s, _) = await pumpEditor(tester, size: const Size(1280, 900));
    s.preferences.toolbarPlacement = ToolbarPlacement.floating;
    await tester.pumpAndSettle();
    final pen = find.byTooltip('Pen (P)');
    final highlighter = find.byTooltip('Highlighter (H)');
    // Across, at the bottom by default.
    expect(tester.getCenter(pen).dy, tester.getCenter(highlighter).dy);

    final grip = find.byTooltip('Drag to move the toolbar');
    final from = tester.getCenter(grip);
    final drag = await tester.startGesture(from);
    for (var i = 1; i <= 20; i++) {
      await drag.moveTo(Offset.lerp(from, const Offset(10, 400), i / 20)!);
      await tester.pump();
    }
    await drag.up();
    await tester.pumpAndSettle();

    expect(s.preferences.toolbarFloat, (0.0, 0.5));
    // Down the left side: tools stacked, near the left edge.
    expect(tester.getCenter(pen).dx, tester.getCenter(highlighter).dx);
    expect(tester.getCenter(highlighter).dy, greaterThan(tester.getCenter(pen).dy));
    expect(tester.getCenter(pen).dx, lessThan(80));
    // Its quick slots follow under the tools.
    expect(
      tester.getCenter(find.byKey(const ValueKey('color-0'))).dy,
      greaterThan(tester.getCenter(find.byTooltip('Laser pointer (K)')).dy),
    );
    expect(tester.takeException(), isNull);

    // Dragged off the edge into the page, it runs across again.
    final back = tester.getCenter(grip);
    final drag2 = await tester.startGesture(back);
    for (var i = 1; i <= 20; i++) {
      await drag2.moveTo(Offset.lerp(back, const Offset(600, 450), i / 20)!);
      await tester.pump();
    }
    await drag2.up();
    await tester.pumpAndSettle();
    expect(ToolbarSlot.isVertical(s.preferences.toolbarFloat), isFalse);
    expect(tester.getCenter(pen).dy, tester.getCenter(highlighter).dy);
    await closeEditor(tester);
  });

  testWidgets('a short pane scrolls the side palette rather than overflowing', (tester) async {
    final (s, _) = await pumpEditor(tester, size: const Size(1280, 420));
    s.preferences
      ..toolbarPlacement = ToolbarPlacement.floating
      ..toolbarFloat = (1.0, 0.5);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Pen (P)'), findsOneWidget);
    await closeEditor(tester);
  });

  group('goldens', () {
    for (final (name, float) in [
      ('toolbar_floating_h', (0.5, 1.0)),
      ('toolbar_floating_v', (0.0, 0.5)),
    ]) {
      testWidgets(name, (tester) async {
        final (s, _) = await pumpEditor(tester, size: const Size(1280, 900));
        s.preferences
          ..toolbarPlacement = ToolbarPlacement.floating
          ..toolbarFloat = float;
        await tester.pumpAndSettle();
        await expectLater(find.byType(EditorScreen), matchesGoldenFile('goldens/$name.png'));
        await closeEditor(tester);
      });
    }

    testWidgets('focus_puck', (tester) async {
      await pumpEditor(tester, size: const Size(1280, 900));
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      await expectLater(find.byType(EditorScreen), matchesGoldenFile('goldens/focus_puck.png'));
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      await closeEditor(tester);
    });
  });
}
