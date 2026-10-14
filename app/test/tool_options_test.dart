import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/documents/templates/paper_options.dart';
import 'package:len/features/editor/editor_tools.dart';
import 'package:len/features/editor/pen/size_scale.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/adaptive_popover.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/color_picker/color_names.dart';
import 'package:len/ui/color_picker/color_swatches.dart';
import 'package:len/ui/focus_ring.dart';
import 'package:len/ui/scroll_fade.dart';

/// The tool options popovers' Reset (with Undo; the pens' resets the feel), the shared size scale,
/// live colour pickers, colour names, the phone sheet's scroll fade and
/// the keyboard focus ring.
void main() {
  late ToolSettings tools;

  setUp(() => tools = ToolSettings());

  Future<void> pump(WidgetTester tester, Widget child, {Size size = const Size(800, 600)}) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => FocusRing(child: child!),
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  /// Opens the options of the toolbar's tool [index] (as its button does).
  Future<void> open(WidgetTester tester, int index) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => editorTools(tools)[index].openOptions(context),
          child: const Text('Edit'),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
  }

  TextButton button(WidgetTester tester, String label) =>
      tester.widget<TextButton>(find.widgetWithText(TextButton, label));

  testWidgets('pen Reset (in the header) restores the feel only; quick colours and sizes stay', (
    tester,
  ) async {
    await open(tester, 0);
    await tester.ensureVisible(find.text('Feel'));
    await tester.tap(find.text('Feel'));
    await tester.pumpAndSettle();
    expect(find.text('Reset'), findsOneWidget, reason: 'one Reset, in the header');
    expect(find.text('Reset feel'), findsNothing);
    await tester.ensureVisible(find.text('Reset'));
    expect(button(tester, 'Reset').onPressed, isNull, reason: 'already the defaults');

    tools.updateConfig(
      InkTool.ballpoint,
      (c) => c
          .withColor(0, 0xFF00AA00)
          .addColor(0xFFFF0000)
          .withWidth(1, 9)
          .copyWith(streamline: 0.8, thinning: 0),
    );
    await tester.pump();
    final custom = tools.configOf(InkTool.ballpoint);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    final config = tools.configOf(InkTool.ballpoint);
    final defaults = PenConfig.defaultsFor(InkTool.ballpoint);
    expect(config.streamline, defaults.streamline);
    expect(config.thinning, defaults.thinning);
    expect(config.colors, [0xFF00AA00, ...defaults.colors.skip(1), 0xFFFF0000]);
    expect(config.widths[1], 9);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(tools.configOf(InkTool.ballpoint), custom);
  });

  test('every default colour of a tool is in its palette, so it shows as picked', () {
    for (final c in PenDefaults.pen.colors) {
      expect(ColorSwatches.palette, contains(c), reason: c.toRadixString(16));
    }
    for (final c in PenDefaults.highlighter.colors) {
      expect(ColorSwatches.highlighter, contains(c), reason: c.toRadixString(16));
    }
    expect(ColorSwatches.palette, contains(const TextData().color));
    expect(ColorSwatches.palette, hasLength(14), reason: 'two rows of seven');
  });

  for (final (index, name, change, read, defaults)
      in <(int, String, void Function(), Object Function(), Object)>[
        (
          2,
          'eraser',
          () => tools.eraser = tools.eraser.copyWith(radius: 30, highlighterOnly: true),
          () => tools.eraser,
          const EraserConfig(),
        ),
        (
          5,
          'text',
          () => tools.textStyle = tools.textStyle.copyWith(fontSize: 40, color: 0xFF00AA00),
          () => tools.textStyle,
          const TextData(),
        ),
        (
          6,
          'laser',
          () => tools.laser = tools.laser.copyWith(size: 20, mode: LaserMode.dot),
          () => tools.laser,
          const LaserConfig(),
        ),
      ]) {
    testWidgets('$name Reset restores every setting, with Undo', (tester) async {
      await open(tester, index);
      change();
      await tester.pump();
      final custom = read();
      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(read(), defaults);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(read(), custom);
    });
  }

  test('the size scale is logarithmic over the ink range, both ways', () {
    final d = PenDefaults.of(InkTool.ballpoint);
    final scale = SizeScale(d);
    expect(scale.toSlider(d.minWidth), 0);
    expect(scale.toSlider(d.maxWidth), closeTo(1, 1e-9));
    expect(scale.toWidth(0.5), closeTo(2.4, 0.06), reason: '√(0.5 × 12)');
    expect(scale.toWidth(scale.toSlider(2.5)), 2.5);
  });

  test('colours have plain names', () {
    expect(colorName(0xFF000000), 'black');
    expect(colorName(0xFFFFFFFF), 'white');
    expect(colorName(0xFF9CA3AF), 'grey');
    expect(colorName(0xFF1F2937), 'dark grey');
    expect(colorName(0xFF1E3A8A), 'dark blue');
    expect(colorName(0xFF1C7ED6), 'blue');
    expect(colorName(0xFFE03131), 'red');
    expect(colorName(0xFFF76707), 'orange');
    expect(colorName(0xFFFACC15), 'yellow');
    expect(colorName(0xFF2F9E44), 'green');
    expect(colorName(0xFF7048E8), 'purple');
    expect(colorName(0xFFF783AC), 'light pink');
    expect(colorName(0xFFC2255C), 'pink');
    expect(colorName(0xFF7F1D1D), 'dark red');
    expect(colorName(0xFF8B5A2B), 'brown');
  });

  testWidgets('the template dialog picks colours live, without Apply', (tester) async {
    var template = const PageTemplate();
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: PaperOptions(template: template, onChanged: (t) => setState(() => template = t)),
          ),
        ),
      ),
      size: const Size(1280, 900),
    );
    await tester.tap(find.byKey(const ValueKey('paper-custom')));
    await tester.pumpAndSettle();
    expect(find.text('Apply'), findsNothing);
    await tester.enterText(find.byType(TextField), 'FFEEDD');
    await tester.pump();
    expect(template.color.paper.toARGB32(), 0xFFFFEEDD, reason: 'applies as it is picked');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(template.color.paper.toARGB32(), 0xFFFFEEDD, reason: 'closing keeps the pick');
  });

  testWidgets('a tall phone sheet fades where it scrolls on', (tester) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showAdaptivePopover<void>(
            context: context,
            builder: (_) => Column(
              children: [for (var i = 0; i < 40; i++) SizedBox(height: 40, child: Text('Row $i'))],
            ),
          ),
          child: const Text('Open'),
        ),
      ),
      size: const Size(390, 844),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(ScrollFade), findsOneWidget);
    expect(find.byKey(const ValueKey('scroll-fade')), findsOneWidget);
  });

  testWidgets('a focus ring shows with the keyboard only', (tester) async {
    await pump(
      tester,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: () {}, child: const Text('One')),
          TextButton(onPressed: () {}, child: const Text('Two')),
        ],
      ),
    );
    final ring = find.byKey(FocusRing.paintKey);
    final primary = AppTheme.light().colorScheme.primary;
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    expect(tester.renderObject(ring.first), isNot(paints..rrect(color: primary)));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(tester.renderObject(ring.first), paints..rrect(color: primary));
  });
}
