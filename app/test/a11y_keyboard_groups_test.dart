import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/settings/settings_screen.dart';

import 'a11y_keyboard_test.dart';
import 'accessibility_test.dart' show pumpScreen, tablet, tapAll, toolOptions;

// Choice groups with the keyboard (the radio group pattern): a segmented
// control or a swatch grid is one Tab stop, at its chosen choice; the
// arrows move inside it and Space or Enter picks.

/// Whether the control with focus reads as selected.
bool focusedSelected(WidgetTester tester) {
  final context = FocusManager.instance.primaryFocus!.context!;
  final data = tester.getSemantics(find.byElementPredicate((e) => e == context)).getSemanticsData();
  return data.flagsCollection.isSelected == Tristate.isTrue;
}

void main() {
  keyboardTest('a segmented control: one stop at the chosen segment, arrows move, Space '
      'picks', (tester) async {
    await pumpScreen(tester, (_) => const SettingsScreen(), size: tablet);
    await tabTo(tester, 'System');
    expect(focusedSelected(tester), isTrue, reason: 'Tab enters at the chosen theme');
    final next = await tabs(tester, 1);
    expect(next.single, isNot(anyOf('Light', 'Dark')), reason: 'Tab leaves the group');
    await tabs(tester, 1, shift: true);
    expect(focused(tester), 'System', reason: 'Shift+Tab comes back to the chosen segment');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(tester), 'Light');
    await press(tester, LogicalKeyboardKey.end);
    expect(focused(tester), 'Dark');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(tester), 'Dark', reason: 'the arrows stop at the end');
    await press(tester, LogicalKeyboardKey.space);
    expect(focusedSelected(tester), isTrue, reason: 'Space picked Dark');
    await press(tester, LogicalKeyboardKey.home);
    expect(focused(tester), 'System');
    await tabs(tester, 1);
    await tabs(tester, 1, shift: true);
    expect(focused(tester), 'Dark', reason: 'Tab now enters at the new choice');
  });

  keyboardTest('a swatch row: one stop at the chosen colour, arrows move, Enter picks', (
    tester,
  ) async {
    await pumpScreen(tester, (_) => const LibraryScreen(), size: tablet);
    await tabTo(tester, 'New notebook');
    await press(tester, LogicalKeyboardKey.enter);
    // The cover colours: the first one reached that reads as selected.
    for (var i = 0; i < 30 && !focusedSelected(tester); i++) {
      await tabs(tester, 1);
    }
    expect(focusedSelected(tester), isTrue, reason: 'Tab enters the covers at the chosen one');
    final chosen = focused(tester);
    await press(tester, LogicalKeyboardKey.arrowRight);
    final other = focused(tester);
    expect(other, isNot(chosen));
    expect(focusedSelected(tester), isFalse, reason: 'moving does not pick');
    await press(tester, LogicalKeyboardKey.enter);
    expect(focusedSelected(tester), isTrue, reason: 'Enter picked it');
    expect(focused(tester), other, reason: 'focus stays on the picked colour');
    final after = await tabs(tester, 1);
    expect(after.single, isNot(chosen), reason: 'Tab leaves the row');
  });

  keyboardTest('the shape options: one stop per row (shape, fill), arrows move', (tester) async {
    await pumpEditor(tester);
    await tapAll(tester, toolOptions('Shapes (S)'));
    final stops = await tabs(tester, 3);
    expect(stops, ['Rectangle', 'No fill', 'Rectangle'], reason: 'Tab cycles in the popover');
    expect(focusedSelected(tester), isTrue);
    final chosen = focused(tester);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(tester), isNot(chosen));
    await press(tester, LogicalKeyboardKey.space);
    expect(focusedSelected(tester), isTrue, reason: 'Space picked it');
  });
}
