import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/pen/pen_options_panel.dart';
import 'package:len/ink/tool_settings.dart';

void main() {
  testWidgets('end styles and taper settings update the next stroke and its preview', (
    tester,
  ) async {
    final tools = ToolSettings();
    addTearDown(tools.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 320, child: PenOptionsPanel(tools: tools)),
          ),
        ),
      ),
    );

    expect(tools.styleFor(InkTool.ballpoint).ends, StrokeEnds.round);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Tapered'));
    await tester.pump();
    expect(tools.styleFor(InkTool.ballpoint).ends, StrokeEnds.tapered);
    expect(tools.styleFor(InkTool.ballpoint).taperStart, greaterThan(0));
    expect(tools.styleFor(InkTool.ballpoint).taperEnd, greaterThan(0));

    await tester.ensureVisible(find.text('End'));
    await tester.tap(find.text('End'));
    await tester.pump();
    expect(tools.styleFor(InkTool.ballpoint).taperStart, 0);
    expect(tools.styleFor(InkTool.ballpoint).taperEnd, greaterThan(0));

    await tester.ensureVisible(find.text('Flat'));
    await tester.tap(find.text('Flat'));
    await tester.pump();
    expect(tools.styleFor(InkTool.ballpoint).ends, StrokeEnds.flat);
    expect(tools.styleFor(InkTool.ballpoint).taperEnd, 0);
    expect(tester.takeException(), isNull);
  });
}
