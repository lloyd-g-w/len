import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/library/library_screen.dart';

import 'a11y_keyboard_test.dart';
import 'accessibility_test.dart' show pumpScreen, tablet;

// Context menus from the keyboard: the Menu key or Shift+F10 on a card,
// a tile or the page opens what a right-click would; Escape closes it and
// gives focus back.

Future<void> shiftF10(WidgetTester tester) => press(tester, LogicalKeyboardKey.f10, shift: true);

/// Tabs until a control whose name starts with [prefix] has focus.
Future<void> tabToStart(WidgetTester tester, String prefix) async {
  for (var i = 0; i < 80; i++) {
    if (focused(tester)?.startsWith(prefix) ?? false) return;
    await tabs(tester, 1);
  }
  fail('Tab never reached $prefix…');
}

void main() {
  keyboardTest('a notebook card: Shift+F10 opens its menu, Escape gives focus back', (
    tester,
  ) async {
    await pumpScreen(tester, (_) => const LibraryScreen(), size: tablet);
    await tabToStart(tester, 'Travel plans');
    final card = focused(tester);
    await shiftF10(tester);
    expect(find.text('Move to trash'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.text('Move to trash'), findsNothing);
    expect(focused(tester), card);
    await press(tester, LogicalKeyboardKey.contextMenu);
    expect(find.text('Move to trash'), findsOneWidget, reason: 'the Menu key too');
    await press(tester, LogicalKeyboardKey.escape);
  });

  keyboardTest('the page: the Menu key opens the canvas menu on its first entry; Escape '
      'goes back to the page', (tester) async {
    await pumpEditor(tester);
    expect(focused(tester), 'canvas');
    await press(tester, LogicalKeyboardKey.contextMenu);
    expect(focused(tester), 'Paste here');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester), 'Select all on page', reason: 'the arrows move in the menu');
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.text('Add text here'), findsNothing);
    expect(focused(tester), 'canvas');
    await shiftF10(tester);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.text('Add text here'), findsNothing, reason: 'Enter chose Select all');
  });

  keyboardTest('page overview: a page is a stop of its own; Enter opens it, Shift+F10 '
      'its menu', (tester) async {
    await pumpEditor(tester);
    await tabTo(tester, 'All pages');
    await press(tester, LogicalKeyboardKey.enter);
    await tabToStart(tester, 'Page 1');
    await shiftF10(tester);
    expect(find.text('Delete page'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.text('Delete page'), findsNothing);
    expect(focused(tester), startsWith('Page 1'));
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.byTooltip('All pages'), findsOneWidget, reason: 'back in the editor');
    expect(find.text('Add page'), findsNothing);
  });
}
