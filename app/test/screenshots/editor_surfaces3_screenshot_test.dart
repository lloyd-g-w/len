import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/features/editor/canvas/canvas_view.dart';
import 'package:len/features/inklab/inklab_screen.dart';
import 'package:len/features/inklab/inklab_stats_bar.dart';

import 'editor_screenshot_test.dart' show pumpEditor;
import 'editor_surfaces_common.dart';
import 'screenshot_harness.dart';

// Editor surfaces with real fonts, part 3: the page navigator, go to page,
// page zoom, the zoom indicator, tabs and the Ink Lab.

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

void main() {
  setUpAll(loadRealFonts);

  // 6. Page navigator, go to page, page zoom.
  for (final screen in [tabletScreen, desktopScreen]) {
    for (final mode in modes) {
      final shot = '${screen.name}_${mode.name}';
      testWidgets('e_pages $shot', (tester) async {
        await guardOverflows('e_pages_$shot', () async {
          await pumpEditor(tester, size: screen.size, mode: mode);
          await tester.tap(find.byTooltip('More ways to add pages'));
          await settle(tester);
          await shoot(tester, 'e_navigator_add_menu_$shot');
          await dismiss(tester, screen.size.center(Offset.zero));
          await tester.tap(find.byTooltip('Go to page'));
          await settle(tester);
          await shoot(tester, 'e_goto_page_$shot');
          await tester.tap(find.text('Cancel'));
          await settle(tester);
          await tester.tap(find.byTooltip('More options'));
          await settle(tester);
          await tester.tap(find.text('Page zoom'));
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
      await dismiss(tester, phone.center(Offset.zero));
      await tester.tap(find.byTooltip('Go to page'), warnIfMissed: false);
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
          await shoot(tester, 'e_zoom_menu_$shot');
          await tester.tap(find.text('Fit content').last);
          await settle(tester);
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
        await tester.tap(find.byTooltip('Open notebooks'));
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
