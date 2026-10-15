import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/ui/end_keeping_text.dart';

void main() {
  const style = TextStyle(fontSize: 10, fontFamily: 'FlutterTest'); // 10 px per character.

  String fit(String text, double width, {int lines = 1}) =>
      fitKeepingEnd(text, style: style, maxWidth: width, maxLines: lines);

  test('keeps the last word when the title is cut', () {
    expect(fit('Electronics — Lecture 12', 150), 'Electronics… 12');
    expect(fit('Electronics — Lecture 12', 240), 'Electronics — Lecture 12');
    // Two lines: the cut comes in the second.
    const long = 'Electronics and Circuits — Lecture 12';
    expect(fit(long, 120, lines: 2), endsWith('… 12'));
    expect(fit(long, 120, lines: 2), startsWith('Electronics and'));
    expect(fit('Calculus — Lecture 12', 100, lines: 2), 'Calculus — Lecture 12');
  });

  test('a last word too wide to keep, or one word, ends in an ellipsis', () {
    expect(fit('Advanced Thermodynamics', 150), 'Advanced Thermodynamics');
    expect(fit('Whiteboard', 50), 'Whiteboard');
  });

  testWidgets('shows the end; screen readers read it whole', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 150,
            child: EndKeepingText('Electronics — Lecture 12', style: style),
          ),
        ),
      ),
    );
    expect(find.text('Electronics… 12'), findsOneWidget);
    expect(find.bySemanticsLabel('Electronics — Lecture 12'), findsOneWidget);
  });
}
