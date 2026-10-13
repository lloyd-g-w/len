import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/ui/hit_overhang.dart';

void main() {
  // A 40 × 40 box whose 48 × 48 child hangs 4 dp over each side, above a
  // tappable 40-dp box, with empty space to its left.
  Future<List<String>> pump(WidgetTester tester) async {
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => HitOverhangScope(child: child!),
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HitOverhang(
                    overhang: const EdgeInsets.all(4),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                    onTap: () => taps.add('overhang'),
                      child: const SizedBox.square(dimension: 48),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps.add('below'),
                    child: const SizedBox.square(dimension: 40),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return taps;
  }

  testWidgets('takes taps on its overhang over empty surface', (tester) async {
    final taps = await pump(tester);
    expect(tester.getSize(find.byType(HitOverhang)), const Size.square(40));
    await tester.tapAt(const Offset(17, 17)); // In the outer padding.
    await tester.tapAt(const Offset(40, 18));
    expect(taps, ['overhang', 'overhang']);
  });

  testWidgets('leaves its neighbour its own box', (tester) async {
    final taps = await pump(tester);
    await tester.tapAt(const Offset(40, 62)); // The neighbour's top 4 dp.
    expect(taps, ['below']);
  });

  testWidgets('does not reach through a route over it', (tester) async {
    final taps = await pump(tester);
    final context = tester.element(find.byType(Column));
    showDialog<void>(context: context, builder: (_) => const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(17, 17));
    expect(taps, isEmpty);
  });
}
