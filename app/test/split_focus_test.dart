import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/chrome/editor_chrome.dart';
import 'package:len/features/editor/chrome/editor_top_bar.dart';
import 'package:len/features/editor/chrome/title_button.dart';
import 'package:len/features/editor/tabs/notebook_tab_strip.dart';
import 'package:len/ui/app_theme.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'split_view_test.dart';

/// How strong the chrome of pane [index] (0: left) is drawn: 1, or
/// [Receding.opacity] while it recedes (its glyphs fade toward the bar).
double chromeOpacity(WidgetTester tester, int index) {
  final chrome = find.byType(EditorChrome).at(index);
  final bar = find.descendant(of: chrome, matching: find.byTooltip('More options'));
  final scheme = Theme.of(tester.element(bar)).colorScheme;
  final ink = AppTheme.scheme(scheme.brightness).onSurface;
  final faded = tester
      .widgetList<AnimatedOpacity>(find.ancestor(of: bar, matching: find.byType(AnimatedOpacity)))
      .map((o) => o.opacity)
      .fold(1.0, (a, b) => a * b);
  final strength = (scheme.onSurface.r - scheme.surface.r) / (ink.r - scheme.surface.r);
  return double.parse((faded * strength).toStringAsFixed(3));
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

  testWidgets('a receded bar keeps its surface; only what is on it fades', (tester) async {
    final (s, _, chemistry) = await pumpWorkspace(tester);
    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    expect(chromeOpacity(tester, 0), 0.6);
    final bar = find.byType(EditorTopBar).at(0);
    final above = tester.widgetList<AnimatedOpacity>(
      find.ancestor(of: bar, matching: find.byType(AnimatedOpacity)),
    );
    expect(above.every((o) => o.opacity == 1), isTrue, reason: 'the bar itself is not faded');
    // Ink is content: the quick colours keep their true colour.
    final swatch = find.descendant(
      of: find.byType(EditorChrome).at(0),
      matching: find.byKey(const ValueKey('color-0')),
    );
    final faded = tester.widgetList<AnimatedOpacity>(
      find.ancestor(of: swatch, matching: find.byType(AnimatedOpacity)),
    );
    expect(faded.every((o) => o.opacity == 1), isTrue, reason: 'ink swatches are not faded');
  });

  testWidgets('split view: both bars name their notebook; the strip marks both', (tester) async {
    final (s, physics, chemistry) = await pumpWorkspace(tester);
    final strip = find.byType(NotebookTabStrip);
    Finder titleIn(int pane) =>
        find.descendant(of: find.byType(EditorTopBar).at(pane), matching: find.byType(TitleButton));
    // Alone, the strip's active tab names the notebook.
    expect(titleIn(0), findsNothing);
    expect(
      find.descendant(of: strip, matching: find.byIcon(Symbols.vertical_split_rounded)),
      findsNothing,
    );

    s.openNotebooks.openSplit(chemistry.id);
    await tester.pumpAndSettle();
    expect(find.descendant(of: titleIn(0), matching: find.text(physics.title)), findsOneWidget);
    expect(find.descendant(of: titleIn(1), matching: find.text(chemistry.title)), findsOneWidget);
    expect(
      find.descendant(of: strip, matching: find.byIcon(Symbols.vertical_split_rounded)),
      findsNWidgets(2),
    );

    s.openNotebooks.closeSplit();
    await tester.pumpAndSettle();
    expect(titleIn(0), findsNothing);
    expect(
      find.descendant(of: strip, matching: find.byIcon(Symbols.vertical_split_rounded)),
      findsNothing,
    );
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
    await tester.pump(Motion.medium); // The chrome comes forward.
    expect(chromeOpacity(tester, 1), 1, reason: 'the drop target reads as live, not greyed');
    await drag.up();
    await tester.pumpAndSettle();
    expect(inkOfNotebook(s, chemistry), hasLength(1));
    s.openNotebooks.closeSplit();
    await tester.pumpAndSettle();
  });
}
