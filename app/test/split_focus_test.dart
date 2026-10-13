import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/chrome/editor_chrome.dart';

import 'split_view_test.dart';

/// The opacity the chrome of pane [index] (0: left) is drawn at.
double chromeOpacity(WidgetTester tester, int index) {
  final chrome = find.byType(EditorChrome).at(index);
  final bar = find.descendant(of: chrome, matching: find.byTooltip('More options'));
  return tester
      .widgetList<AnimatedOpacity>(find.ancestor(of: bar, matching: find.byType(AnimatedOpacity)))
      .map((o) => o.opacity)
      .fold(1.0, (a, b) => a * b);
}

void main() {
  testWidgets('the pane in use has full chrome; the other recedes until touched', (tester) async {
    final (s, physics, chemistry) = await pumpWorkspace(tester);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    // The pane just opened takes the keyboard: it is in use.
    expect(chromeOpacity(tester, 1), 1);
    expect(chromeOpacity(tester, 0), 0.6);

    // Writing in the left pane draws there and brings its chrome forward.
    await drawIn(tester, 0);
    await tester.pumpAndSettle();
    expect(inkOfNotebook(s, physics), hasLength(1), reason: 'the first contact still draws');
    expect(chromeOpacity(tester, 0), 1);
    expect(chromeOpacity(tester, 1), 0.6);

    // And back.
    await drawIn(tester, 1);
    await tester.pumpAndSettle();
    expect(inkOfNotebook(s, chemistry), hasLength(1));
    expect(chromeOpacity(tester, 1), 1);
    expect(chromeOpacity(tester, 0), 0.6);

    // Closing the split: nothing is dimmed.
    s.openNotebooks.closeSplit();
    await tester.pumpAndSettle();
    expect(chromeOpacity(tester, 0), 1);
  });

  testWidgets('a pane a selection would drop into is not dimmed', (tester) async {
    final (s, physics, chemistry) = await pumpWorkspace(tester);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    await drawIn(tester, 0);
    await tester.pumpAndSettle();
    expect(chromeOpacity(tester, 1), 0.6);

    final left = tester.getCenter(paneOf(0)) + const Offset(-100, 0);
    await tester.tapAt(left, buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all on page'));
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(
      left + const Offset(30, 10),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 1; i <= 20; i++) {
      await drag.moveTo(left + Offset(30 + i * 40.0, 10));
      await tester.pump();
    }
    expect(find.text('Drop to copy here'), findsOneWidget);
    expect(chromeOpacity(tester, 1), 1, reason: 'the drop target reads as live, not greyed');
    await drag.up();
    await tester.pumpAndSettle();
    expect(inkOfNotebook(s, chemistry), hasLength(1));
    s.openNotebooks.closeSplit();
    await tester.pumpAndSettle();
  });
}
