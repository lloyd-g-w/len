import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'text_flow_editor_test.dart' show field, lines, openNotebook, typeBox;

/// For each semantics node from the edited text box's field up to the
/// root: its id and the ids of it and its siblings in traversal order.
List<(int, List<int>)> _orders(WidgetTester tester) {
  final out = <(int, List<int>)>[];
  for (SemanticsNode? n = tester.getSemantics(field); n?.parent != null; n = n.parent) {
    final siblings = n!.parent!.debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder);
    out.add((n.id, [for (final s in siblings) s.id]));
  }
  return out;
}

void main() {
  // With a screen reader on the web, the field's text input lives in its
  // semantics node's element: moved in the page (its node, or one around
  // it, changing places with a sibling), it loses the keyboard focus and
  // typing goes nowhere. A box grown past the top of the view (typed down
  // the page, or flowing onto the next) once sorted itself before the
  // editor's toolbar.
  testWidgets('the edited box keeps its place in the semantics order as it grows past the top', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await openNotebook(tester);
    await typeBox(tester, const Offset(80, 200), lines(2));
    final before = _orders(tester);
    await tester.enterText(field, lines(80));
    await tester.pumpAndSettle();
    final after = _orders(tester);
    expect(after.map((o) => o.$1), before.map((o) => o.$1), reason: 'the same ancestors');
    for (var i = 0; i < before.length; i++) {
      final common = before[i].$2.toSet().intersection(after[i].$2.toSet());
      expect(
        after[i].$2.where(common.contains).toList(),
        before[i].$2.where(common.contains).toList(),
        reason: 'the order around node ${before[i].$1} (level $i from the field)',
      );
    }
    semantics.dispose();
  });
}
