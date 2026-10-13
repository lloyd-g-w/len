import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/tools/selection_menu.dart';

Finder _more() => find.descendant(of: find.byType(SelectionMenu), matching: find.byTooltip('More'));

/// Runs the selection menu's action [label]: its button on the pill, or
/// its row in the pill's ⋯.
Future<void> selectionAction(WidgetTester tester, String label) async {
  final button = find.descendant(of: find.byType(SelectionMenu), matching: find.byTooltip(label));
  if (button.evaluate().isNotEmpty) {
    await tester.tap(button.first);
  } else {
    await tester.tap(_more());
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
  }
  // Bounded: what the action opens may animate for good (a spinner).
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Whether the selection menu offers [label] (on the pill or in ⋯); leaves
/// ⋯ closed.
Future<bool> selectionOffers(WidgetTester tester, String label) async {
  final menu = find.byType(SelectionMenu);
  if (menu.evaluate().isEmpty) return false;
  if (find.descendant(of: menu, matching: find.byTooltip(label)).evaluate().isNotEmpty) {
    return true;
  }
  if (_more().evaluate().isEmpty) return false;
  await tester.tap(_more());
  await tester.pumpAndSettle();
  final offered = find.text(label).evaluate().isNotEmpty;
  await tester.tapAt(Offset.zero); // Closes ⋯.
  await tester.pumpAndSettle();
  return offered;
}
