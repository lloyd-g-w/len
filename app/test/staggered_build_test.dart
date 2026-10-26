import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/menus.dart';
import 'package:material_symbols_icons/symbols.dart';

Widget _button({ValueChanged<int>? onSelected}) => MenuIconButton<int>(
  tooltip: 'Options',
  icon: const Icon(Symbols.more_horiz_rounded),
  staggered: true,
  onSelected: onSelected ?? (_) {},
  items: () => [const MenuRow(value: 1, label: 'One')],
);

void main() {
  for (final tap in MaterialTapTargetSize.values) {
    testWidgets('a staggered menu button: its glyph stays put ($tap)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(materialTapTargetSize: tap),
          home: Scaffold(
            body: Align(alignment: Alignment.topRight, child: _button()),
          ),
        ),
      );
      expect(find.byType(IconButton), findsNothing, reason: 'built a frame later');
      final before = tester.getRect(find.byType(Icon));
      await tester.pump();
      expect(find.byType(IconButton), findsOneWidget);
      expect(tester.getRect(find.byType(Icon)), before);
    });
  }

  testWidgets('the placeholder opens the menu too', (tester) async {
    int? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(child: _button(onSelected: (v) => chosen = v)),
        ),
      ),
    );
    await tester.tap(find.byType(Icon));
    await tester.pumpAndSettle();
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    expect(chosen, 1);
  });

  testWidgets('waits while its list scrolls, at most a few a frame', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 40; i++) Row(children: [_button()]),
            ],
          ),
        ),
      ),
    );
    final drag = await tester.startGesture(tester.getCenter(find.byType(ListView)));
    await drag.moveBy(const Offset(0, -300));
    await tester.pump();
    await drag.moveBy(const Offset(0, -10));
    await tester.pump();
    expect(find.byType(IconButton), findsNothing, reason: 'scrolling');
    await drag.up();
    await tester.pump();
    expect(find.byType(IconButton).evaluate().length, lessThanOrEqualTo(4));
    await tester.pumpAndSettle();
    expect(
      find.byType(IconButton).evaluate().length,
      find.byType(MenuIconButton<int>).evaluate().length,
    );
  });
}
