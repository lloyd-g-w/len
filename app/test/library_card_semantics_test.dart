import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/library/notebook_card.dart';

import 'library_ui_test.dart' show addNotebook, pumpSeeded;

/// Found in the real web build (tool/web_explore.py): once the ⋯ showed
/// (hover, focus, always on touch) a card was a group, not a button, for
/// screen readers, and the hidden ⋯ was out of their reach.
void main() {
  testWidgets('a card is a button named by its title, with or without the ⋯ showing', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpSeeded(tester, (s) => addNotebook(s, 'Algebra'));
    final card = find.byType(NotebookCard);

    SemanticsNode node() => tester.getSemantics(
      find.descendant(of: card, matching: find.bySemanticsLabel(RegExp(r'^Algebra\n'))).first,
    );
    void expectButton() {
      final data = node().getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.label, startsWith('Algebra\n'));
      // The ⋯ is its own button, reachable while hidden too.
      final more = find.semantics.byPredicate(
        (n) => n.getSemanticsData().tooltip == 'More' && !n.isInvisible,
      );
      expect(more, findsOne);
    }

    expectButton();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(card));
    await tester.pumpAndSettle();
    expectButton();
    await mouse.removePointer();
    semantics.dispose();
  });
}
