@Tags(['screenshots'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/chrome/editor_tips.dart';
import 'package:len/features/editor/chrome/editor_top_bar.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
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
      // A slot's own editor: tap the selected colour, then the selected
      // width (the second).
      await tester.tap(find.byKey(const ValueKey('color-0')));
      await settle(tester);
      await shoot(tester, 'slot_colour_$m');
      await closePopover(tester);
      await tester.tap(find.byKey(const ValueKey('width-1')));
      await settle(tester);
      await shoot(tester, 'slot_size_$m');
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
        // Picking the lasso shows a one-time tip (it goes with the next tool).
        if (shot == 'lasso') await shoot(tester, 'tip_lasso_$m');
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
    await tester.ensureVisible(find.text('Quick colours and sizes'));
    await tester.tap(find.text('Quick colours and sizes'));
    await settle(tester);
    await tester.ensureVisible(find.byTooltip('More quick colours'));
    await tester.tap(find.byTooltip('More quick colours'));
    await tester.tap(find.byTooltip('More quick sizes'));
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

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('toolbar phone: pen options and slot editors as sheets ${mode.name}', (
      tester,
    ) async {
      final m = mode.name;
      await openEditor(tester, phone, 2, mode);
      await tester.tap(find.byType(ToolSwitcherButton));
      await settle(tester);
      await tester.tap(find.text('Pen'));
      await settle(tester);
      await shoot(tester, 'phone_pen_sheet_$m');
      await tester.tapAt(const Offset(195, 60));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('color-0')));
      await settle(tester);
      await shoot(tester, 'phone_slot_colour_$m');
      await tester.tapAt(const Offset(195, 60));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('width-1')));
      await settle(tester);
      await shoot(tester, 'phone_slot_size_$m');
      expect(tester.takeException(), isNull);
    });
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('toolbar phone: lasso and laser sheets ${mode.name}', (tester) async {
      await openEditor(tester, phone, 2, mode);
      for (final (tool, shot) in [('Lasso', 'lasso'), ('Laser', 'laser')]) {
        await tester.tap(find.byType(ToolSwitcherButton));
        await settle(tester);
        await tester.tap(find.text(tool));
        await settle(tester);
        await tester.longPress(find.byType(ToolSwitcherButton));
        await settle(tester);
        if (shot == 'laser') {
          await tester.tap(find.text('When I stop'));
          await settle(tester);
        }
        await shoot(tester, 'phone_${shot}_sheet_${mode.name}');
        await tester.tapAt(const Offset(195, 60));
        await settle(tester);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('toolbar phone: highlighter sheet at 1.3x text, dark', (tester) async {
    await openEditor(tester, phone, 2, ThemeMode.dark, textScale: 1.3);
    await tester.tap(find.byType(ToolSwitcherButton));
    await settle(tester);
    await tester.tap(find.text('Highlighter'));
    await settle(tester);
    await tester.longPress(find.byType(ToolSwitcherButton));
    await settle(tester);
    await shoot(tester, 'phone_highlighter_sheet_text13');
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

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('scribble to erase: the preview and its tip ${mode.name}', (tester) async {
      final m = mode.name;
      await openEditor(
        tester,
        tablet,
        2,
        mode,
        setUp: (s) {
          s.preferences.stylusOnly = true;
          s.settings.markTipSeen(EditorTip.penButton.name);
        },
      );
      // Scribble over the second line's first word, the pen still down.
      final doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
      final frame = doc.layout.frameOf(0)!;
      final word = doc.surfaces.surfaceOf(doc.pages.first.id).model.strokeById('w5')!;
      final box = Rect.fromPoints(
        doc.viewport.toScreen(word.bounds.topLeft + frame.topLeft),
        doc.viewport.toScreen(word.bounds.bottomRight + frame.topLeft),
      ).inflate(4);
      final pen = await tester.startGesture(box.topLeft, kind: PointerDeviceKind.stylus);
      var ms = 0;
      for (var k = 0; k < 8; k++) {
        final y = box.top + box.height * (k + 1) / 9;
        for (var i = 1; i <= 10; i++) {
          final t = k.isEven ? i / 10 : 1 - i / 10;
          await pen.moveTo(
            Offset(box.left + box.width * t, y),
            timeStamp: Duration(milliseconds: ms += 6),
          );
        }
        await tester.pump();
      }
      final model = doc.surfaces.surfaceOf(doc.pages.first.id).model;
      expect(model.isHidden(word.id), isTrue, reason: 'drawn dimmed instead');
      // Let the dimming fade in.
      await tester.pump(const Duration(milliseconds: 200));
      await shoot(tester, 'scribble_preview_$m');
      await pen.up(timeStamp: Duration(milliseconds: ms + 6));
      await settle(tester);
      // The second pick of the eraser teaches the gesture once.
      for (final tool in ['Eraser (E)', 'Pen (P)', 'Eraser (E)']) {
        await tester.tap(find.byTooltip(tool));
        await settle(tester);
      }
      await shoot(tester, 'tip_scribble_$m');
      expect(tester.takeException(), isNull);
    });
  }
}
