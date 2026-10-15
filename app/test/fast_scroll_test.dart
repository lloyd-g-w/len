import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/ui/fast_scroll.dart';

void main() {
  Future<(FastScroll, List<bool>)> list(WidgetTester tester, ScrollController controller) async {
    tester.view
      ..physicalSize = const Size(400, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fast = FastScroll(controller);
    addTearDown(fast.dispose);
    final heard = <bool>[];
    fast.addListener(() => heard.add(fast.value));
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 50,
          itemBuilder: (context, i) => Text('$i'),
        ),
      ),
    );
    return (fast, heard);
  }

  testWidgets('a fast drag is fast until it slows or rests; a slow one never', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final (fast, heard) = await list(tester, controller);
    final drag = await tester.startGesture(const Offset(200, 300));
    // 300 px/s: slow.
    for (var i = 0; i < 20; i++) {
      await drag.moveBy(const Offset(0, -5));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(heard, isEmpty);
    // 6,000 px/s (10 viewports a second): fast from the second frame.
    await drag.moveBy(const Offset(0, -100));
    await tester.pump(const Duration(milliseconds: 16));
    expect(fast.value, isTrue);
    await drag.moveBy(const Offset(0, -100));
    await tester.pump(const Duration(milliseconds: 16));
    expect(fast.value, isTrue);
    // Held still: it rests.
    await tester.pump(const Duration(milliseconds: 150));
    expect(fast.value, isFalse);
    // Moving fast again, then slowly.
    for (final dy in const <double>[-100, -100, -100, -3, -3]) {
      await drag.moveBy(Offset(0, dy));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(fast.value, isFalse);
    expect(heard, [true, false, true, false]);
    await drag.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a fling is fast at once, and not once it ends', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final (fast, heard) = await list(tester, controller);
    await tester.fling(find.byType(ListView), const Offset(0, -300), 8000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(fast.value, isTrue);
    await tester.pumpAndSettle();
    expect(fast.value, isFalse);
    expect(heard.first, isTrue);
    expect(heard.last, isFalse);
  });
}
