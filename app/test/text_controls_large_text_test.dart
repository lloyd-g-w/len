import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/tools/text_options_panel.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/app_theme.dart';

import 'content_golden_test.dart' show text;
import 'content_tools_ui_test.dart';

/// Whether the text [finder] shows is drawn whole: on one line where
/// [oneLine], and not cut by its box.
void _whole(WidgetTester tester, Finder finder, {bool oneLine = false}) {
  final p = tester.renderObject<RenderParagraph>(finder);
  expect(p.size.height, greaterThanOrEqualTo(p.textSize.height - 0.01), reason: 'cut');
  if (oneLine) {
    expect(p.size.width, greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity) - 0.01));
  }
}

void main() {
  void largeText(WidgetTester tester) {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  testWidgets('at 2× text the Text options\' rows show their whole labels', (tester) async {
    largeText(tester);
    final tools = ToolSettings();
    addTearDown(tools.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 320, child: TextOptionsPanel(tools: tools)),
          ),
        ),
      ),
    );
    _whole(tester, find.text('Paragraph spacing'));
    _whole(tester, find.text('Font'));
  });

  testWidgets('at 2× text the phone format bar\'s size stays on one line', (tester) async {
    largeText(tester);
    await openCanvas(
      tester,
      size: const Size(390, 844),
      seed: (s, nb) => s.elements.save([
        text(nb.id, const Offset(20, 120), const TextData(text: 'Hello', fontSize: 24), width: 300),
      ]),
    );
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(60, 130)]);
    await tester.pumpAndSettle();
    _whole(tester, find.byKey(const ValueKey('text-size')), oneLine: true);
    expect(find.text('24'), findsOneWidget);
  });
}
