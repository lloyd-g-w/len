import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/chrome/editor_top_bar.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/editor_toolbar.dart';
import 'package:len/features/editor/toolbar/tool_switcher.dart';

import '../support/handwriting.dart';
import 'screenshot_harness.dart';

// Screenshots of the pen toolbar and its popovers; the editor chrome's are in
// editor_screenshot_test.dart.

const phone = Size(390, 844);
const tabletPortrait = Size(800, 1280);
const tablet = Size(1280, 800);
const desktop = Size(1440, 900);

/// A notebook whose first page carries realistic handwriting.
Notebook writtenNotebook(AppServices s) {
  final n = s.notebooks.create(
    title: 'Lecture notes',
    kind: NotebookKind.paged,
    paper: PaperStyle.wideRuled,
    coverColor: 0xFF3B5BDB,
  );
  final page = s.pages.pagesOf(n.id).first.id;
  final hw = Handwriting(seed: 5);
  var id = 0;
  Stroke ink(
    List<StrokePoint> pts, {
    int color = 0xFF1A2233,
    double width = 2.5,
    InkTool tool = InkTool.ballpoint,
  }) => Stroke(
    id: 'w${id++}',
    surfaceId: page,
    tool: tool,
    color: color,
    width: width,
    points: [for (final p in pts) StrokePoint(p.x * 2.2, p.y * 2.2, p.pressure)],
    createdAt: id,
  );
  s.strokes.save([
    ink(
      hw.line(const Offset(48, 100), const Offset(120, 101)),
      tool: InkTool.highlighter,
      color: 0xFFFACC15,
      width: 20,
    ),
    for (var line = 0; line < 4; line++) ...[
      ink(
        hw.cursive(Offset(50, 80.0 + line * 26), [e, l, l, e, u, e]),
        color: line == 0 ? 0xFF1C4ED8 : 0xFF1A2233,
      ),
      ink(hw.oval(Offset(108, 75.5 + line * 26), 4, 4.5)),
      ink(hw.letterS(Offset(118, 80.0 + line * 26), 9)),
      ink(hw.cursive(Offset(134, 80.0 + line * 26), [u, e, l, e])),
    ],
  ]);
  return n;
}

Future<AppServices> openEditor(
  WidgetTester tester,
  Size size,
  double dpr,
  ThemeMode mode, {
  double textScale = 1,
  void Function(AppServices)? setUp,
}) async {
  setWindow(tester, size, dpr: dpr);
  final services = seededServices();
  addTearDown(services.dispose);
  setUp?.call(services);
  final notebook = writtenNotebook(services);
  await pumpApp(
    tester,
    services,
    EditorScreen(notebook: notebook),
    mode: mode,
    textScale: textScale,
  );
  return services;
}

Rect toolbarRect(WidgetTester tester) => tester.getRect(find.byType(EditorToolbar)).inflate(8);

/// The top chrome block (bar and attached tool row).
Rect topRect(WidgetTester tester) {
  final bar = tester.getRect(find.byType(EditorTopBar));
  return Rect.fromLTRB(bar.left, bar.top, bar.right, bar.bottom + 8);
}

Future<void> closePopover(WidgetTester tester) async {
  await tester.tapAt(const Offset(4, 400));
  await settle(tester);
}

void main() {
  setUpAll(loadRealFonts);

  for (final (name, size, dpr) in [
    ('phone', phone, 2.0),
    ('tablet_portrait', tabletPortrait, 2.0),
    ('tablet', tablet, 2.0),
    ('desktop', desktop, 1.5),
  ]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('toolbar in editor $name ${mode.name}', (tester) async {
        await openEditor(tester, size, dpr, mode);
        expect(tester.takeException(), isNull);
        await shoot(tester, 'editor_${name}_${mode.name}');
        await shoot(tester, 'toolbar_${name}_${mode.name}', crop: toolbarRect(tester));
      });
    }
  }

  testWidgets('toolbar at 1.3x text (tablet portrait and phone)', (tester) async {
    await openEditor(tester, tabletPortrait, 2, ThemeMode.light, textScale: 1.3);
    expect(tester.takeException(), isNull);
    await shoot(tester, 'toolbar_text13_tablet', crop: topRect(tester));
    await openEditor(tester, phone, 2, ThemeMode.dark, textScale: 1.3);
    expect(tester.takeException(), isNull);
    await shoot(tester, 'toolbar_text13_phone');
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('tool options popovers ${mode.name}', (tester) async {
      await openEditor(tester, tablet, 2, mode);
      final m = mode.name;
      // Pen: tap the active tool.
      await tester.tap(find.byTooltip('Pen (P)'));
      await settle(tester);
      await shoot(tester, 'popover_pen_$m');
      await tester.tap(find.text('Feel'));
      await settle(tester);
      await shoot(tester, 'popover_pen_feel_$m');
      await closePopover(tester);
      // From a slot: tap the selected width (the second).
      await tester.tap(find.byKey(const ValueKey('width-1')));
      await settle(tester);
      await shoot(tester, 'popover_from_slot_$m');
      await closePopover(tester);
      for (final (tooltip, shot) in [
        ('Highlighter (H)', 'highlighter'),
        ('Eraser (E)', 'eraser'),
        ('Lasso (L)', 'lasso'),
        ('Shapes (S)', 'shapes'),
        ('Text (T)', 'text'),
        ('Laser pointer (K)', 'laser'),
      ]) {
        await tester.tap(find.byTooltip(tooltip));
        await settle(tester);
        await shoot(tester, 'toolbar_${shot}_$m', crop: topRect(tester));
        await tester.tap(find.byTooltip(tooltip));
        await settle(tester);
        await shoot(tester, 'popover_${shot}_$m');
        await closePopover(tester);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pen options: custom colour and more slots', (tester) async {
    await openEditor(tester, tablet, 2, ThemeMode.light);
    await tester.tap(find.byTooltip('Pen (P)'));
    await settle(tester);
    await tester.tap(find.byTooltip('More quick colours'));
    await tester.tap(find.byTooltip('More quick widths'));
    await settle(tester);
    await tester.tap(find.text('Custom'));
    await settle(tester);
    await shoot(tester, 'popover_pen_custom');
    await closePopover(tester);
    await shoot(tester, 'toolbar_pen_more_slots', crop: topRect(tester));
    expect(tester.takeException(), isNull);
  });

  testWidgets('insert and more menus', (tester) async {
    await openEditor(tester, tablet, 2, ThemeMode.light);
    await tester.tap(find.byTooltip('Insert'));
    await settle(tester);
    await shoot(tester, 'menu_insert');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await tester.tap(find.byTooltip('More options'));
    await settle(tester);
    await shoot(tester, 'menu_more');
    await tester.tap(find.text('View'));
    await settle(tester);
    await shoot(tester, 'menu_more_view');
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating toolbar', (tester) async {
    await openEditor(
      tester,
      tablet,
      2,
      ThemeMode.dark,
      setUp: (s) => s.preferences.toolbarPlacement = ToolbarPlacement.floating,
    );
    await shoot(tester, 'editor_floating_dark');
    expect(tester.takeException(), isNull);
  });

  testWidgets('toolbar phone: pen options as a sheet', (tester) async {
    await openEditor(tester, phone, 2, ThemeMode.light);
    await tester.tap(find.byKey(const ValueKey('color-0')));
    await settle(tester);
    await shoot(tester, 'phone_pen_sheet');
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('toolbar phone: tool switcher ${mode.name}', (tester) async {
      await openEditor(tester, phone, 2, mode);
      await tester.tap(find.byType(ToolSwitcherButton));
      await settle(tester);
      await shoot(tester, 'phone_tool_switcher_${mode.name}');
      await tester.tap(find.text('Eraser'));
      await settle(tester);
      await shoot(tester, 'toolbar_phone_eraser_${mode.name}', crop: toolbarRect(tester));
      await tester.tap(find.byTooltip('More options'));
      await settle(tester);
      await shoot(tester, 'phone_more_menu_${mode.name}');
      expect(tester.takeException(), isNull);
    });
  }
}
