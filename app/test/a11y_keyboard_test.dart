import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/editor_screen.dart';

import 'accessibility_test.dart' show physics, pumpScreen, tablet;
import 'screenshots/screenshot_harness.dart' show settle;

// Len with a keyboard alone: Tab and Shift+Tab reach every control in a
// sensible order, arrows move within toolbars, menus and popovers take
// focus in and give it back to their opener on Escape. (Screen reader
// names and target sizes: accessibility_test.dart.)

/// What a screen reader calls the control with keyboard focus: its
/// tooltip, else its label; 'canvas' for the editor's own focus (the
/// page), null when nothing has focus.
String? focused(WidgetTester tester) {
  final node = FocusManager.instance.primaryFocus;
  final context = node?.context;
  if (node == null || context == null) return null;
  if (node.debugLabel == 'EditorScreen') return 'canvas';
  final data = tester.getSemantics(find.byElementPredicate((e) => e == context)).getSemanticsData();
  return data.tooltip.isNotEmpty ? data.tooltip : data.label;
}

/// Presses [key] (with Shift when [shift]) and lets what it opens settle.
Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
  await settle(tester);
}

/// The focus stops Tab (or Shift+Tab) visits from here, [count] of them.
Future<List<String?>> tabs(WidgetTester tester, int count, {bool shift = false}) async {
  final seen = <String?>[];
  for (var i = 0; i < count; i++) {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    seen.add(focused(tester));
  }
  return seen;
}

/// Tabs until [name] has focus.
Future<void> tabTo(WidgetTester tester, String name) async {
  for (var i = 0; i < 80; i++) {
    if (focused(tester) == name) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  fail('Tab never reached $name');
}

/// A widget test with semantics on (names come from the semantics tree).
void keyboardTest(String description, Future<void> Function(WidgetTester tester) body) =>
    testWidgets(description, (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await body(tester);
      } finally {
        semantics.dispose();
      }
    });

Future<void> pumpEditor(WidgetTester tester) async {
  await pumpScreen(tester, (s) => EditorScreen(notebook: physics(s)), size: tablet);
}

const colour = 'Colour 1 (1)';
const size = 'Size 0.65 mm';

void main() {
  group('editor chrome', () {
    keyboardTest('Tab: bar, the chosen tool, Insert, quick slots, actions, page; '
        'Shift+Tab back', (tester) async {
      await pumpEditor(tester);
      expect(focused(tester), 'canvas', reason: 'the page has focus when the editor opens');
      const order = [
        'Back',
        'All pages',
        'Rename',
        'Pen (P)',
        'Insert',
        colour,
        size,
        'Record audio',
        'More options',
        'canvas',
      ];
      expect(await tabs(tester, order.length), order);
      expect(await tabs(tester, 3, shift: true), ['More options', 'Record audio', size]);
    });

    keyboardTest('arrows run along the toolbar, past the tools to the slots, and stop '
        'at its ends', (tester) async {
      await pumpEditor(tester);
      await tabTo(tester, 'Pen (P)');
      final right = <String?>[];
      for (var i = 0; i < 9; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        right.add(focused(tester));
      }
      expect(right, [
        'Highlighter (H)',
        'Eraser (E)',
        'Lasso (L)',
        'Shapes (S)',
        'Text (T)',
        'Laser pointer (K)',
        'Insert',
        colour,
        'Colour 2 (2)',
      ]);
      await tabTo(tester, 'Pen (P)');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(focused(tester), 'Pen (P)', reason: 'the first tool is the toolbar\'s start');
    });

    keyboardTest('Space picks the focused tool; Tab then stops at it', (tester) async {
      await pumpEditor(tester);
      await tabTo(tester, 'Pen (P)');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.space);
      expect(focused(tester), 'Highlighter (H)', reason: 'focus stays on the picked tool');
      await press(tester, LogicalKeyboardKey.escape);
      expect(focused(tester), 'canvas');
      await tabTo(tester, 'All pages');
      expect(await tabs(tester, 2), ['Rename', 'Highlighter (H)']);
    });

    for (final (opener, first) in [('More options', 'Search in notebook'), ('Insert', 'Image…')]) {
      keyboardTest('$opener: Enter opens it on its first item, Escape gives focus back', (
        tester,
      ) async {
        await pumpEditor(tester);
        await tabTo(tester, opener);
        await press(tester, LogicalKeyboardKey.enter);
        expect(focused(tester), first);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focused(tester), isNot(first), reason: 'arrows move in the menu');
        await press(tester, LogicalKeyboardKey.escape);
        expect(find.text(first), findsNothing);
        expect(focused(tester), opener);
      });
    }

    keyboardTest('the chosen tool opens its options; Escape comes back to it', (tester) async {
      await pumpEditor(tester);
      await tabTo(tester, 'Pen (P)');
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.text('Size'), findsWidgets, reason: 'the pen options are open');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focused(tester), 'Pick from page', reason: 'focus moved into the popover');
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.text('Custom'), findsNothing);
      expect(focused(tester), 'Pen (P)');
    });

    keyboardTest('the selected colour slot opens its editor; Escape comes back to it', (
      tester,
    ) async {
      await pumpEditor(tester);
      await tabTo(tester, colour);
      await press(tester, LogicalKeyboardKey.enter);
      expect(focused(tester), isNot(colour), reason: 'the colour editor took focus');
      await press(tester, LogicalKeyboardKey.escape);
      expect(focused(tester), colour);
    });
  });
}
