import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/editor_toolbar.dart';
import 'package:len/features/editor/tool_switcher.dart';

import '../support/handwriting.dart';
import 'screenshot_harness.dart';

// Screenshots of the pen toolbar and its popovers; the editor chrome's are in
// editor_screenshot_test.dart.

const phone = Size(390, 844);
const tabletPortrait = Size(800, 1280);
const tablet = Size(1280, 800);

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

Future<void> openEditor(WidgetTester tester, Size size, double dpr, ThemeMode mode) async {
  setWindow(tester, size, dpr: dpr);
  final services = seededServices();
  addTearDown(services.dispose);
  final notebook = writtenNotebook(services);
  await pumpApp(tester, services, EditorScreen(notebook: notebook), mode: mode);
}

Rect toolbarRect(WidgetTester tester) => tester.getRect(find.byType(EditorToolbar)).inflate(8);

void main() {
  setUpAll(loadRealFonts);

  for (final (name, size, dpr) in [
    ('phone', phone, 2.0),
    ('tablet_portrait', tabletPortrait, 2.0),
    ('tablet', tablet, 2.0),
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

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('toolbar popovers ${mode.name}', (tester) async {
      await openEditor(tester, tablet, 2, mode);
      final m = mode.name;
      // Colour editor: tap the selected colour.
      await tester.tap(find.byKey(const ValueKey('color-0')));
      await settle(tester);
      await shoot(tester, 'popover_color_$m');
      await tester.tapAt(const Offset(640, 700));
      await settle(tester);
      // Width editor.
      await tester.tap(find.byKey(const ValueKey('width-1')));
      await settle(tester);
      await shoot(tester, 'popover_width_$m');
      await tester.tapAt(const Offset(640, 700));
      await settle(tester);
      // Pen settings.
      await tester.tap(find.byTooltip('Pen settings'));
      await settle(tester);
      await shoot(tester, 'popover_pen_$m');
      await tester.tapAt(const Offset(640, 700));
      await settle(tester);
      // Highlighter strip and settings.
      await tester.tap(find.byTooltip('Highlighter (H)'));
      await settle(tester);
      await shoot(tester, 'toolbar_highlighter_$m', crop: toolbarRect(tester));
      await tester.tap(find.byTooltip('Highlighter settings'));
      await settle(tester);
      await shoot(tester, 'popover_highlighter_$m');
      await tester.tapAt(const Offset(640, 700));
      await settle(tester);
      await tester.tap(find.byTooltip('Eraser (E)'));
      await settle(tester);
      await shoot(tester, 'toolbar_eraser_$m', crop: toolbarRect(tester));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('toolbar phone: colour editor as a sheet', (tester) async {
    await openEditor(tester, phone, 2, ThemeMode.light);
    await tester.tap(find.byKey(const ValueKey('color-0')));
    await settle(tester);
    await shoot(tester, 'phone_color_sheet');
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
      expect(tester.takeException(), isNull);
    });

    testWidgets('toolbar with tool names ${mode.name}', (tester) async {
      setWindow(tester, tablet, dpr: 2);
      final services = seededServices();
      addTearDown(services.dispose);
      services.preferences.toolbarLabels = true;
      await pumpApp(
        tester,
        services,
        EditorScreen(notebook: writtenNotebook(services)),
        mode: mode,
      );
      await shoot(tester, 'toolbar_labels_${mode.name}', crop: toolbarRect(tester));
      expect(tester.takeException(), isNull);
    });
  }
}
