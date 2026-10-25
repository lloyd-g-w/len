import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('pen: stabiliser 30 % by default, off at 0, up to 100 %; Reset restores the feel', (
    tester,
  ) async {
    await pump(tester, PenOptionsPanel(tools: tools));
    expect(find.text('30%'), findsOneWidget, reason: 'the pen\'s default stabiliser');
    await drag(tester, 'Stabiliser', -400);
    expect(tools.configOf(InkTool.ballpoint).streamline, 0);
    expect(find.text('Off'), findsOneWidget);
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

  testWidgets('highlighter: opacity, stabiliser, flat or round ends, straight lines', (
    tester,
  ) async {
    await pump(tester, HighlighterOptionsPanel(tools: tools));
    expect(find.text('50%'), findsOneWidget, reason: 'stabiliser default');
    // Pressure sensitivity (off by default) is not offered.
    expect(find.text('Pressure sensitivity'), findsNothing);
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

  testWidgets('highlighter: Snap to text, on by default, a switch by keyboard; Reset restores', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, HighlighterOptionsPanel(tools: tools));
    PenConfig config() => tools.configOf(InkTool.highlighter);
    expect(config().snapToText, isTrue);
    final row = find.text('Snap to text');
    expect(
      tester.getSemantics(row),
      isSemantics(
        label: 'Snap to text\nHighlights over PDF text cover whole words',
        hasToggledState: true,
        isToggled: true,
        isFocusable: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(row);
    await tester.pump();
    expect(config().snapToText, isFalse);
    expect(tester.getSemantics(row), isSemantics(hasToggledState: true, isToggled: false));
    expect(tools.configOf(InkTool.ballpoint).snapToText, isTrue, reason: 'the pen is untouched');
    // The row is a focus stop: Space toggles it back, and off again.
    Focus.of(tester.element(row)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(config().snapToText, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(config().snapToText, isFalse);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(config(), PenConfig.defaultsFor(InkTool.highlighter));
    semantics.dispose();
  });

  testWidgets('shapes: one line points to hold to snap in Settings → Writing (R8-33)', (
    tester,
  ) async {
    await pump(tester, ShapeOptionsPanel(tools: tools));
    expect(find.text('Hold the pen still to snap (Settings → Writing)'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    tools.holdToStraighten = false;
    await tester.pump();
    expect(find.text('Hold to snap is off (Settings → Writing)'), findsOneWidget);
  });

  testWidgets('shapes: with a keyboard, curves say Enter and Esc rather than Shift', (
    tester,
  ) async {
    Targets.debugTouchFirst = false;
    addTearDown(() => Targets.debugTouchFirst = null);
    await pump(tester, ShapeOptionsPanel(tools: tools));
    expect(find.text('Hold Shift for regular shapes and 15° lines'), findsOneWidget);
    tools.shape = ShapeKind.curve;
    await tester.pump();
    expect(find.text('Hold Shift for regular shapes and 15° lines'), findsNothing);
    expect(find.text('Enter finishes a curve, Esc drops it'), findsOneWidget);
  });

  testWidgets('shapes: Reset in the header restores the rectangle and no fill (R12-9)', (
    tester,
  ) async {
    await pump(tester, ShapeOptionsPanel(tools: tools));
    final reset = find.widgetWithText(TextButton, 'Reset');
    expect(tester.widget<TextButton>(reset).onPressed, isNull, reason: 'at the defaults');
    tools
      ..shape = ShapeKind.ellipse
      ..shapeFill = const ShapeFill.tint(0.25);
    await tester.pump();
    await tester.tap(reset);
    await tester.pump();
    expect(tools.shape, ShapeKind.rectangle);
    expect(tools.shapeFill, ShapeFill.none);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(tools.shape, ShapeKind.ellipse);
    expect(tools.shapeFill, const ShapeFill.tint(0.25));
  });

  testWidgets('shapes: each caption line fits the popover on one line (R12-9)', (tester) async {
    await loadFonts();
    await pump(tester, ShapeOptionsPanel(tools: tools));
    final caption = Theme.of(tester.element(find.byType(ShapeOptionsPanel))).textTheme.bodySmall;
    final lines = find.descendant(
      of: find.byType(ShapeOptionsPanel),
      matching: find.byWidgetPredicate((w) => w is Text && w.style == caption),
    );
    expect(lines, findsWidgets);
    for (final e in lines.evaluate()) {
      final box = e.renderObject! as RenderBox;
      expect(
        box.size.height,
        lessThan(2 * caption!.fontSize!),
        reason: '${(e.widget as Text).data} wraps',
      );
    }
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

  testWidgets('the ink options are one flat panel: no colours, no size, no submenus', (
    tester,
  ) async {
    for (final (i, ink) in [(0, InkTool.ballpoint), (1, InkTool.highlighter)]) {
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => editorTools(tools)[i].openOptions(context),
            child: const Text('Edit'),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.byType(ColorDot), findsNothing, reason: '$ink: colours are the quick slots');
      expect(find.text('Size'), findsNothing, reason: '$ink: sizes are the quick slots');
      expect(find.textContaining('Quick'), findsNothing, reason: '$ink: counts are in Settings');
      expect(find.text('Feel'), findsNothing, reason: '$ink: nothing collapsed');
      expect(find.text('Taper length'), findsNothing);
      expect(find.text('Stabiliser'), findsOneWidget);
      expect(find.text('Ends'), findsOneWidget);
      await tester.tapAt(const Offset(790, 590)); // Closes the popover.
      await tester.pumpAndSettle();
    }
  });

  test('sizes read in millimetres on the page', () {
    expect(formatWidth(2.5), '0.65 mm', reason: 'to 0.05 mm below 1 mm');
    expect(formatWidth(2.27), '0.6 mm');
    expect(formatWidth(4), '1.1 mm');
    expect(formatWidth(48), '13 mm');
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
