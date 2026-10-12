import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/pen/eraser_options_panel.dart';
import 'package:len/features/editor/pen/highlighter_options_panel.dart';
import 'package:len/features/editor/pen/pen_options_panel.dart';
import 'package:len/features/editor/pen/slot_editors.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/color_picker/color_rows.dart';

import 'content_golden_test.dart' show loadFonts;

/// The pen, highlighter and eraser settings panels and the recent colours
/// of the colour slot editor.
void main() {
  late ToolSettings tools;

  setUp(() => tools = ToolSettings());

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: Padding(padding: const EdgeInsets.all(Gaps.lg), child: child),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> drag(WidgetTester tester, String label, double dx) async {
    final slider = find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
      matching: find.byType(Slider),
    );
    await tester.drag(slider, Offset(dx, 0));
    await tester.pump();
  }

  testWidgets('pen: stabiliser off at 0 and up to 100 %; Reset restores the feel', (tester) async {
    await pump(tester, PenOptionsPanel(tools: tools));
    expect(find.text('Off'), findsOneWidget, reason: 'the pen has no stabiliser by default');
    expect(find.text('Smooths shaky lines; the ink trails the pen a little'), findsOneWidget);
    await drag(tester, 'Stabiliser', 400);
    expect(tools.configOf(InkTool.ballpoint).streamline, 1);
    expect(find.text('100%'), findsOneWidget);
    await drag(tester, 'Pressure sensitivity', -400);
    expect(tools.configOf(InkTool.ballpoint).thinning, 0);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(tools.configOf(InkTool.ballpoint), PenConfig.defaultsFor(InkTool.ballpoint));
    expect(find.text('Straight lines'), findsNothing);
  });

  testWidgets('highlighter: stabiliser and straight lines', (tester) async {
    await pump(tester, HighlighterOptionsPanel(tools: tools));
    expect(find.text('50%'), findsOneWidget, reason: 'stabiliser default');
    await drag(tester, 'Stabiliser', -400);
    expect(tools.configOf(InkTool.highlighter).streamline, 0);
    expect(find.text('Off'), findsOneWidget);
    await tester.tap(find.text('Straight lines'));
    await tester.pump();
    expect(tools.configOf(InkTool.highlighter).straight, isTrue);
    // Neither the stabiliser nor hold to snap applies to straight lines.
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders.last.onChanged, isNull);
    await tester.tap(find.text('Hold to snap shapes'));
    await tester.pump();
    expect(tools.holdToStraighten, isTrue);
    expect(tools.configOf(InkTool.ballpoint).straight, isFalse);
  });

  testWidgets('eraser: auto-deselect', (tester) async {
    await pump(tester, EraserOptionsPanel(tools: tools));
    expect(tools.eraser.autoDeselect, isFalse);
    await tester.tap(find.text('Auto-deselect'));
    await tester.pump();
    expect(tools.eraser.autoDeselect, isTrue);
  });

  testWidgets('a picked slot colour becomes recent; a recent colour applies', (tester) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => openColorSlotEditor(context, tools, InkTool.ballpoint, 1),
          child: const Text('Edit'),
        ),
      ),
    );
    tools.addRecentColor(0xFF00AA00);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(RecentColorsRow), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('#00aa00').first);
    await tester.pump();
    expect(tools.configOf(InkTool.ballpoint).colors[1], 0xFF00AA00);
    expect(tools.recentColors, [0xFF00AA00], reason: 'noted when the editor closes');

    tools.updateConfig(InkTool.ballpoint, (c) => c.withColor(1, 0xFF0000FF));
    await tester.tapAt(const Offset(790, 590)); // Closes the popover.
    await tester.pumpAndSettle();
    expect(tools.recentColors, [0xFF0000FF, 0xFF00AA00]);
  });

  testWidgets('golden: pen and highlighter settings', (tester) async {
    await loadFonts();
    tester.view
      ..physicalSize = const Size(700, 520)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tools.updateConfig(InkTool.highlighter, (c) => c.copyWith(straight: true));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(Gaps.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 320, child: PenOptionsPanel(tools: tools)),
                const SizedBox(width: Gaps.lg + Gaps.xs),
                SizedBox(width: 320, child: HighlighterOptionsPanel(tools: tools)),
              ],
            ),
          ),
        ),
      ),
    );
    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/pen_panels.png'));
  });
}
