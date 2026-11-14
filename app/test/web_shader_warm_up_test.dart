import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/ui/web_shader_warm_up.dart';

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

CustomPaint _paint(WidgetTester tester) => tester.widget<CustomPaint>(
  find.descendant(of: find.byType(WebShaderWarmUp), matching: find.byType(CustomPaint)).first,
);

void main() {
  testWidgets('the warm-up paints beneath the app for a few frames, then goes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: WebShaderWarmUp(enabled: true, child: _Probe())),
    );
    final probe = tester.state(find.byType(_Probe));
    // Its image is decoded first.
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && _paint(tester).painter == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    expect(_paint(tester).painter, isNotNull);
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(_paint(tester).painter, isNull);
    expect(tester.state(find.byType(_Probe)), same(probe), reason: 'the app stays in place');
  });

  testWidgets('natively nothing is painted', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WebShaderWarmUp(child: _Probe())));
    await tester.pump();
    expect(_paint(tester).painter, isNull);
  });
}
