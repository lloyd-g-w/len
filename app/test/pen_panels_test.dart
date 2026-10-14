import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/editor_tools.dart';
import 'package:len/features/editor/pen/eraser_options_panel.dart';
import 'package:len/features/editor/pen/highlighter_options_panel.dart';
import 'package:len/features/editor/pen/ink_slots.dart';
import 'package:len/features/editor/pen/pen_options_panel.dart';
import 'package:len/features/editor/tools/colour_sheet.dart';
import 'package:len/features/editor/tools/fill_choices.dart';
import 'package:len/features/editor/tools/shape_options_panel.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/color_dot.dart';

import 'content_golden_test.dart' show loadFonts;

/// The pen, highlighter and eraser settings panels and the recent colours
/// of the tool options popover.
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

  testWidgets('highlighter: the pen engine\'s settings, flat or round ends, straight lines', (
    tester,
  ) async {
    await pump(tester, HighlighterOptionsPanel(tools: tools));
    expect(find.text('50%'), findsOneWidget, reason: 'stabiliser default');
    expect(find.text('Off'), findsOneWidget, reason: 'pressure sensitivity default');
    await drag(tester, 'Pressure sensitivity', 400);
    expect(tools.configOf(InkTool.highlighter).thinning, 1);
    await drag(tester, 'Stabiliser', -400);
    expect(tools.configOf(InkTool.highlighter).streamline, 0);
    expect(find.text('Off'), findsOneWidget, reason: 'the stabiliser');
    // Ends: a chisel (the default) or round; no taper.
    expect(find.text('Tapered'), findsNothing);
    expect(tools.configOf(InkTool.highlighter).ends.style, StrokeEnds.flat);
    await tester.tap(find.text('Round'));
    await tester.pump();
    expect(tools.styleFor(InkTool.highlighter).ends, StrokeEnds.round);
    await tester.tap(find.text('Straight lines'));
    await tester.pump();
    expect(tools.configOf(InkTool.highlighter).straight, isTrue);
    // The stabiliser doesn't apply to straight lines.
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders.last.onChanged, isNull);
    expect(tools.configOf(InkTool.ballpoint).straight, isFalse);
    // Hold to snap has one home, Settings → Writing.
    expect(find.text('Hold to snap'), findsNothing);
  });

  testWidgets('shapes: one line points to hold to snap in Settings → Writing (R8-33)', (
    tester,
  ) async {
    await pump(tester, ShapeOptionsPanel(tools: tools));
    expect(find.text('Hold the pen still to snap a shape (Settings → Writing)'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    tools.holdToStraighten = false;
    await tester.pump();
    expect(find.text('Hold to snap is off in Settings → Writing'), findsOneWidget);
  });

  testWidgets('shapes: the fill row is inert for lines and arrows', (tester) async {
    await pump(tester, ShapeOptionsPanel(tools: tools));
    bool inert() => tester
        .widgetList<IgnorePointer>(
          find.ancestor(of: find.byType(FillChoices), matching: find.byType(IgnorePointer)),
        )
        .any((w) => w.ignoring);
    tools.shape = ShapeKind.rectangle;
    await tester.pump();
    expect(inert(), isFalse);
    tools.shape = ShapeKind.line;
    await tester.pump();
    expect(inert(), isTrue);
    expect(find.byType(FillChoices), findsOneWidget, reason: 'kept, so the panel does not jump');
  });

  testWidgets('the pen has no gesture switches: they live in Settings → Writing (R8-26)', (
    tester,
  ) async {
    final pen = editorTools(tools).first;
    await pump(tester, SingleChildScrollView(child: Builder(builder: pen.options!)));
    await tester.tap(find.text('Feel'));
    await tester.pumpAndSettle();
    expect(find.text('Reset'), findsOneWidget, reason: 'in the header, for the feel');
    expect(find.text('Hold to snap'), findsNothing);
    expect(find.text('Scribble to erase'), findsNothing);
  });

  testWidgets('the eraser mentions scribbling while it is on (R8-26)', (tester) async {
    await pump(tester, EraserOptionsPanel(tools: tools));
    expect(find.text('Or scribble over ink with the pen'), findsOneWidget);
    tools.scribbleToErase = false;
    await tester.pump();
    expect(find.text('Or scribble over ink with the pen'), findsNothing);
  });

  testWidgets('a picked slot colour becomes recent; a recent colour applies', (tester) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () {
            tools.selectColor(1);
            editorTools(tools).first.openOptions(context);
          },
          child: const Text('Edit'),
        ),
      ),
    );
    tools.addRecentColor(0xFF00AA00);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Recent'), findsOneWidget);
    await tester.tap(dot(0xFF00AA00).first);
    await tester.pump();
    expect(tools.configOf(InkTool.ballpoint).colors[1], 0xFF00AA00);
    expect(tools.recentColors, [0xFF00AA00], reason: 'noted when the popover closes');

    tools.updateConfig(InkTool.ballpoint, (c) => c.withColor(1, 0xFF0000FF));
    await tester.tapAt(const Offset(790, 590)); // Closes the popover.
    await tester.pumpAndSettle();
    expect(tools.recentColors, [0xFF0000FF, 0xFF00AA00]);
  });

  test('sizes read in millimetres on the page', () {
    expect(formatWidth(2.5), '0.65 mm', reason: 'to 0.05 mm below 1 mm');
    expect(formatWidth(2.27), '0.6 mm');
    expect(formatWidth(4), '1.1 mm');
    expect(formatWidth(48), '13 mm');
  });

  testWidgets('the highlighter offers light colours; the size slider is in mm', (tester) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => editorTools(tools)[1].openOptions(context),
          child: const Text('Edit'),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(dot(0xFF000000), findsNothing, reason: 'no black highlighter');
    expect(dot(0xFFFACC15), findsOneWidget);
    expect(find.text(formatWidth(tools.configOf(InkTool.highlighter).width)), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
  });

  testWidgets('the colour popover applies live and closing keeps the last pick', (tester) async {
    int? result;
    final live = <int>[];
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await pickColour(
            context,
            title: 'Text colour',
            initial: 0xFF000000,
            tools: tools,
            live: live.add,
          ),
          child: const Text('Pick'),
        ),
      ),
    );
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    expect(find.text('Apply'), findsNothing);
    expect(find.byType(TextField), findsNothing, reason: 'the palette first');
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '00AA00');
    await tester.pump();
    expect(live.last, 0xFF00AA00);
    await tester.tapAt(const Offset(790, 590)); // Closes the popover.
    await tester.pumpAndSettle();
    expect(result, 0xFF00AA00);
    expect(tools.recentColors, [0xFF00AA00]);
  });

  testWidgets('golden: pen and highlighter settings', (tester) async {
    await loadFonts();
    tester.view
      ..physicalSize = const Size(700, 640)
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

/// The colour swatch of [argb].
Finder dot(int argb) => find.byWidgetPredicate((w) => w is ColorDot && w.color == argb);
