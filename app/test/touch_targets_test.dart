import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/color_dot.dart';
import 'package:len/ui/even_grid.dart';

Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(child: SizedBox(width: 300, child: child)),
      ),
    ),
  );
}

void main() {
  // Targets are decided by input (touch-first or pointer), not width.
  for (final (name, size, touch) in [
    ('touch', const Size(360, 740), true),
    ('pointer', const Size(1280, 800), false),
    ('wide touch', const Size(1280, 800), true),
  ]) {
    testWidgets('swatch grids: 48 dp cells on touch, compact with a pointer ($name)', (
      tester,
    ) async {
      Targets.debugTouchFirst = touch;
      addTearDown(() => Targets.debugTouchFirst = null);
      int? tapped;
      await pumpAt(
        tester,
        size,
        EvenGrid(
          itemExtent: 40,
          minItemExtent: 32,
          touchTargets: true,
          children: [
            for (var i = 0; i < 14; i++)
              ColorDot(color: 0xFF000000 + i, size: 40, selected: false, onTap: () => tapped = i),
          ],
        ),
      );
      final cell = tester.getRect(find.byType(ColorDot).first);
      expect(cell.width, touch ? greaterThanOrEqualTo(48) : lessThan(48));
      // A tap in the cell's corner, outside the round dot, still counts.
      await tester.tapAt(cell.topLeft + const Offset(2, 2));
      expect(tapped, 0);
    });
  }
}
