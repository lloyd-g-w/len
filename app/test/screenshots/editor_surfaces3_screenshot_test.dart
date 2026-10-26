@Tags(['screenshots'])
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/canvas/canvas_minimap.dart';
import 'package:len/features/editor/canvas/canvas_view.dart';
import 'package:len/features/editor/zoom/zoom_box.dart';
import 'package:len/features/inklab/inklab_screen.dart';
import 'package:len/features/inklab/inklab_stats_bar.dart';

import 'editor_screenshot_test.dart' show pumpEditor;
import 'editor_surfaces_common.dart';
import 'screenshot_harness.dart';

// Editor surfaces with real fonts, part 3: the page navigator, go to page,
// page zoom, the zoom indicator, tabs and the Ink Lab.

final _mapPaint = find.descendant(
  of: find.byType(CanvasMinimap),
  matching: find.byType(CustomPaint),
);

/// Two fingers spread on the minimap: it zooms in on itself.
Future<void> _pinchMap(WidgetTester tester) async {
  final at = tester.getCenter(_mapPaint.last);
  final a = await tester.startGesture(at - const Offset(15, 0), pointer: 7);
  final b = await tester.startGesture(at + const Offset(15, 0), pointer: 8);
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await a.moveBy(const Offset(-5, 0));
    await b.moveBy(const Offset(5, 0));
    await tester.pump();
  }
  await a.up();
  await b.up();
  await settle(tester);
}

/// Draws a few strokes in the Ink Lab with a stylus.
Future<void> _scribble(WidgetTester tester, Offset start) async {
  for (var line = 0; line < 3; line++) {
    final pen = await tester.startGesture(
      start + Offset(0, line * 60.0),
      kind: PointerDeviceKind.stylus,
    );
    for (var i = 0; i < 40; i++) {
      await pen.moveBy(Offset(6, math.sin(i / 2) * 9));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await pen.up();
  }
  await tester.pump(InkLabStatsBar.period);
}

/// A word written with a stylus from [start]: loops along the line.
Future<void> _word(WidgetTester tester, Offset start) async {
  final pen = await tester.startGesture(start, kind: PointerDeviceKind.stylus);
  for (var i = 0; i < 28; i++) {
    await pen.moveBy(Offset(2.6 + math.cos(i / 1.6) * 3, -math.sin(i / 1.6) * 7));
    await tester.pump(const Duration(milliseconds: 8));
  }
  await pen.up();
  await tester.pump();
}

/// A canvas with writing in four places far apart.
Notebook _atlas(AppServices s, {PaperColor paper = PaperColor.white}) {
  final n = s.notebooks.create(
    title: 'Atlas',
    kind: NotebookKind.canvas,
    paper: PaperStyle.dotted,
    paperColor: paper,
    coverColor: 0xFF0B7285,
  );
  s.strokes.save([
    ...inkLines(n.id, const Offset(-150, -90), lines: 1, color: 0xFF1C4ED8, prefix: 'h'),
    ...inkLines(n.id, const Offset(-150, -10), seed: 3),
    ...inkLines(n.id, const Offset(1800, 700), lines: 6, width: 900, seed: 5, prefix: 'a'),
    ...inkLines(n.id, const Offset(-1600, 1900), lines: 4, width: 1400, seed: 7, prefix: 'b'),
    ...inkLines(n.id, const Offset(3400, -1200), lines: 2, width: 500, seed: 9, prefix: 'c'),
  ]);
  return n;
}

void main() {
  setUpAll(loadRealFonts);

  // 6. Page navigator, go to page, page zoom.
  for (final screen in [tabletScreen, desktopScreen]) {
    for (final mode in modes) {
      final shot = '${screen.name}_${mode.name}';
      testWidgets('e_pages $shot', (tester) async {
        await guardOverflows('e_pages_$shot', () async {
          await pumpEditor(tester, size: screen.size, mode: mode);
          await tester.tap(find.byTooltip('Insert'));
          await settle(tester);
          await shoot(tester, 'e_navigator_add_menu_$shot');
          await dismiss(tester, screen.size.center(Offset.zero));
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: screen.size.center(Offset.zero),
              scrollDelta: const Offset(0, 500),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tap(find.byTooltip('Go to page'));
          await settle(tester);
          await shoot(tester, 'e_goto_page_$shot');
          await tester.tap(find.text('Cancel'));
          await settle(tester);
          await tester.tap(find.byTooltip('More options'));
          await settle(tester);
          await tester.tap(find.text('View'));
          await settle(tester);
          await shoot(tester, 'e_page_zoom_menu_$shot');
          await tester.tap(find.text('Page'));
          await settle(tester);
          await shoot(tester, 'e_page_menu_$shot');
        });
      });
    }
  }

  testWidgets('e_goto_page phone large text', (tester) async {
    await guardOverflows('e_goto_page_phone_large_text', () async {
      await pumpEditor(tester, size: phone, dpr: 2, phoneInsets: true);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      await settle(tester);
      await tester.tap(find.byTooltip('More options'));
      await settle(tester);
      await tester.tap(find.text('Page'));
      await settle(tester);
      await shoot(tester, 'e_page_menu_phone_large_text');
      await dismiss(tester, const Offset(40, 700)); // Beside the menu.
      await tester.sendEventToBinding(
        const PointerScrollEvent(position: Offset(180, 480), scrollDelta: Offset(0, 500)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byTooltip('Go to page'));
      await settle(tester);
      await shoot(tester, 'e_goto_page_phone_large_text');
    });
  });

  // 6. Zoom indicator (canvas).
  for (final screen in [phoneScreen, tabletScreen]) {
    for (final mode in modes) {
      final shot = '${screen.name}_${mode.name}';
      testWidgets('e_zoom $shot', (tester) async {
        await guardOverflows('e_zoom_$shot', () async {
          final s = bareServices();
          await pumpNotebook(tester, s, whiteboard(s), screen: screen, mode: mode);
          final nav = tester.widget<CanvasView>(find.byType(CanvasView)).navigation;
          nav.zoomTo(2.5);
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          await shoot(tester, 'e_zoom_indicator_$shot');
          await tester.tap(find.textContaining(RegExp(r'^\d+%$')));
          await settle(tester);
          expect(find.text('Back to start'), findsOneWidget);
          await shoot(tester, 'e_zoom_menu_$shot');
          await tester.tap(find.text('Fit content').last);
          await settle(tester);
        });
      });
    }
  }

  // 6a. Minimap (canvas): content far apart, the frame on the view; ⋯ → View;
  // its own menu (long-press).
  for (final screen in [phoneScreen, tabletScreen]) {
    for (final mode in modes) {
      final shot = '${screen.name}_${mode.name}';
      testWidgets('e_minimap $shot', (tester) async {
        await guardOverflows('e_minimap_$shot', () async {
          final s = bareServices();
          s.settings.canvasMinimap = true;
          await pumpNotebook(tester, s, _atlas(s), screen: screen, mode: mode);
          await settle(tester);
          await shoot(tester, 'e_minimap_$shot');
          final nav = tester.widget<CanvasView>(find.byType(CanvasView)).navigation;
          nav.zoomTo(1);
          await settle(tester);
          nav.centreOn(const Offset(2250, 850));
          await settle(tester);
          await shoot(tester, 'e_minimap_zoomed_$shot');
          // The map zoomed in on itself (two fingers): the fit button above it.
          await _pinchMap(tester);
          await shoot(tester, 'e_minimap_map_zoomed_$shot');
          await tester.longPress(find.byType(CanvasMinimap));
          await settle(tester);
          await shoot(tester, 'e_minimap_menu_$shot');
          await dismiss(tester, screen.size.center(Offset.zero));
          await tester.tap(find.byTooltip('More options'));
          await settle(tester);
          await tester.tap(find.text('View'));
          await settle(tester);
          await shoot(tester, 'e_minimap_view_menu_$shot');
        });
      });
    }
  }

  testWidgets('e_minimap dark paper', (tester) async {
    await guardOverflows('e_minimap_dark_paper', () async {
      final s = bareServices();
      s.settings.canvasMinimap = true;
      await pumpNotebook(tester, s, _atlas(s, paper: PaperColor.dark), screen: tabletScreen);
      await settle(tester);
      await shoot(tester, 'e_minimap_dark_paper');
      // Zoomed and panned away from the view: a mark on the edge points at it.
      final nav = tester.widget<CanvasView>(find.byType(CanvasView)).navigation;
      nav.zoomTo(1);
      await settle(tester);
      nav.centreOn(const Offset(2250, 850));
      await settle(tester);
      await _pinchMap(tester);
      final map = tester.getCenter(_mapPaint.last);
      for (var i = 0; i < 4; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(position: map, scrollDelta: const Offset(-120, 120)),
        );
      }
      await settle(tester);
      await shoot(tester, 'e_minimap_edge_dark_paper');
    });
  });

  // 6b. Zoom window: ⋯ → View → Zoom window, then words written in the box.
  for (final screen in [phoneScreen, tabletScreen]) {
    for (final mode in modes) {
      final shot = '${screen.name}_${mode.name}';
      testWidgets('e_zoom_window $shot', (tester) async {
        await guardOverflows('e_zoom_window_$shot', () async {
          await pumpEditor(
            tester,
            size: screen.size,
            dpr: screen.dpr,
            mode: mode,
            phoneInsets: screen.insets,
          );
          await tester.tap(find.byTooltip('More options'));
          await settle(tester);
          // Phones have it at the top of ⋯, wider screens in View.
          if (find.text('Zoom window').evaluate().isEmpty) {
            await tester.tap(find.text('View'));
            await settle(tester);
          }
          await tester.tap(find.text('Zoom window'));
          await settle(tester);
          final box = tester.getRect(find.byType(ZoomBox));
          for (var word = 0; word < 3; word++) {
            await _word(tester, box.topLeft + Offset(24 + word * 90.0, box.height * 0.55));
          }
          await settle(tester);
          await shoot(tester, 'e_zoom_window_$shot');
          // Left-handed, from the box's own menu: the box docks at the top.
          await tester.tap(find.byTooltip('Zoom window options'));
          await settle(tester);
          await shoot(tester, 'e_zoom_window_menu_$shot');
          await tester.tap(find.text('Left-handed'));
          await settle(tester);
          await shoot(tester, 'e_zoom_window_left_$shot');
        });
      });
    }
  }

  // 7. Tabs.
  void moreTabs(AppServices s) {
    final all = s.notebooks.list();
    for (final prefix in ['Journal', 'Recipes', 'Ideas', 'Spanish', 'Meeting', 'Whiteboard']) {
      s.openNotebooks.open(all.firstWhere((n) => n.title.startsWith(prefix)));
    }
    s.openNotebooks.open(all.firstWhere((n) => n.title.startsWith('Physics')));
  }

  for (final screen in [portraitScreen, desktopScreen]) {
    for (final mode in modes) {
      final shot = 'e_tabs_${screen.name}_${mode.name}';
      testWidgets(shot, (tester) async {
        await guardOverflows(shot, () async {
          await pumpEditor(tester, size: screen.size, mode: mode, before: moreTabs);
          await shoot(tester, shot);
        });
      });
    }
  }

  for (final mode in modes) {
    testWidgets('e_tab_switcher phone ${mode.name}', (tester) async {
      await guardOverflows('e_tab_switcher_phone_${mode.name}', () async {
        await pumpEditor(
          tester,
          size: phone,
          dpr: 2,
          mode: mode,
          phoneInsets: true,
          before: moreTabs,
        );
        await tester.tap(find.byTooltip('More options'));
        await settle(tester);
        await tester.tap(find.textContaining('Open notebooks'));
        await settle(tester);
        await shoot(tester, 'e_tab_switcher_phone_${mode.name}');
      });
    });
  }

  // 8. Ink Lab.
  for (final screen in [phoneScreen, desktopScreen]) {
    for (final mode in modes) {
      final shot = 'e_inklab_${screen.name}_${mode.name}';
      testWidgets(shot, (tester) async {
        await guardOverflows(shot, () async {
          setWindow(tester, screen.size, dpr: screen.dpr);
          if (screen.insets) {
            tester.view.padding = FakeViewPadding(top: 28 * screen.dpr, bottom: 20 * screen.dpr);
            addTearDown(tester.view.resetPadding);
          }
          final s = bareServices();
          addTearDown(s.dispose);
          await pumpApp(tester, s, const InkLabScreen(), mode: mode);
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(InkLabStatsBar), findsOneWidget);
          await _scribble(tester, Offset(40, screen.size.height * 0.3));
          await settle(tester);
          await shoot(tester, shot);
          // Leave the lab so its timers and recorder are released.
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(milliseconds: 500));
        });
      });
    }
  }
}
