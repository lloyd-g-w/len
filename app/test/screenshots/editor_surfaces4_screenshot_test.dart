import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/paper_pattern.dart';
import 'package:len/features/documents/templates/user_templates.dart';
import 'package:len/features/editor/chrome/editor_chrome.dart';
import 'package:len/features/editor/chrome/editor_tips.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_screen.dart';

import '../images_test.dart' show pngOf;
import 'editor_screenshot_test.dart' show pumpEditor;
import 'editor_surfaces_common.dart';
import 'screenshot_harness.dart';

// Editor surfaces with real fonts, part 4: snack bars, the gesture HUD and
// tips in dark mode, editor dialogs, and error states.

const _screens = [phoneScreen, desktopScreen];

Future<void> _menu(WidgetTester tester, List<String> path) async {
  await tester.tap(find.byTooltip('More options'));
  await settle(tester);
  for (final item in path) {
    await tester.tap(find.text(item).last);
    await settle(tester);
  }
}

/// ⋯ → Page → "Add page after" held down: the template chooser.
Future<void> _insertPageWithTemplate(WidgetTester tester) async {
  await _menu(tester, ['Page']);
  await tester.longPress(find.text('Add page after').last);
  await settle(tester);
}

/// Renames from the title (tap it).
Future<void> _rename(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Rename'));
  await settle(tester);
}

Future<void> _open(WidgetTester tester, Screen screen, ThemeMode mode, {bool tabs = false}) =>
    pumpEditor(
      tester,
      size: screen.size,
      dpr: screen.dpr,
      mode: mode,
      phoneInsets: screen.insets,
      tabs: tabs,
    );

Future<void> _cancel(WidgetTester tester) async {
  await tester.tap(find.text('Cancel').last);
  await settle(tester);
}

/// The screen position of the planner link to [target] on page [index].
Offset _linkOn(WidgetTester tester, int index, Paper target) {
  final view = find.byType(PagedDocumentView);
  final doc = tester.widget<PagedDocumentView>(view).controller;
  final page = doc.pages[index];
  final link = PaperPattern.of(
    page.paper,
    page.bounds,
    page: page.bounds,
  ).links.firstWhere((l) => l.target == target);
  final frame = doc.layout.frameOf(index)!;
  return tester.getTopLeft(view) + doc.viewport.toScreen(frame.topLeft + link.rect.center);
}

void main() {
  setUpAll(loadRealFonts);

  // 9. Snack bars.
  for (final screen in _screens) {
    for (final mode in modes) {
      final shot = '${screen.name}_${mode.name}';
      testWidgets('e_snack $shot', (tester) async {
        await guardOverflows('e_snack_$shot', () async {
          await _open(tester, screen, mode);
          await _menu(tester, ['Page', 'Delete page']);
          await shoot(tester, 'e_snack_page_deleted_$shot');
          await tester.tap(find.text('Undo'));
          await settle(tester);

          // Save page as template: the name prompt, then the snack bar.
          // From inside the editor (as its menu does), under its
          // MessageInsets: the snack bar clears the bottom chrome.
          final editor = tester.element(find.byType(EditorChrome).first);
          unawaited(
            UserTemplates.savePng(
              editor,
              pngOf(40, 56, r: 250, g: 250, b: 245),
              size: const Size(794, 1123),
              name: 'Physics — Mechanics, page 1',
            ),
          );
          await settle(tester);
          await shoot(tester, 'e_dialog_save_template_$shot');
          await tester.tap(find.text('Save'));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
          await settle(tester);
          expect(find.text('Saved to My templates'), findsOneWidget);
          await shoot(tester, 'e_snack_saved_template_$shot');
        });
      });
    }
  }

  for (final mode in modes) {
    testWidgets('e_snack one page, stylus detected ${mode.name}', (tester) async {
      await guardOverflows('e_snack_misc_${mode.name}', () async {
        final s = bareServices();
        final nb = s.notebooks.create(
          title: 'Meeting notes',
          kind: NotebookKind.paged,
          paper: PaperStyle.gridLarge,
          coverColor: 0xFF1971C2,
        );
        await pumpNotebook(tester, s, nb, screen: phoneScreen, mode: mode);
        await _menu(tester, ['Page', 'Delete page']);
        await shoot(tester, 'e_snack_last_page_phone_${mode.name}');
        ScaffoldMessenger.of(tester.element(find.byType(EditorScreen))).removeCurrentSnackBar();
        await settle(tester);
        // The first pen stroke: "Stylus detected" (no tip after it).
        final pen = await tester.startGesture(
          const Offset(120, 420),
          kind: PointerDeviceKind.stylus,
        );
        for (var i = 1; i <= 12; i++) {
          await pen.moveTo(Offset(120 + i * 12.0, 420 + (i.isEven ? 8 : -8)));
        }
        await pen.up();
        await settle(tester);
        await shoot(tester, 'e_snack_stylus_detected_phone_${mode.name}');
      });
    });
  }

  // 9. The gesture HUD and tips, dark.
  for (final screen in [phoneScreen, tabletScreen]) {
    testWidgets('e_hud ${screen.name} dark', (tester) async {
      await guardOverflows('e_hud_${screen.name}_dark', () async {
        await _open(tester, screen, ThemeMode.dark);
        final c = screen.size.center(Offset.zero);
        final a = await tester.startGesture(c - const Offset(60, 0));
        final b = await tester.startGesture(c + const Offset(60, 0));
        await a.up();
        await b.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await shoot(tester, 'e_hud_${screen.name}_dark');
        await settle(tester);
      });
    });
  }

  testWidgets('e_tips phone dark', (tester) async {
    await guardOverflows('e_tips_phone_dark', () async {
      await pumpEditor(
        tester,
        size: phone,
        dpr: 2,
        mode: ThemeMode.dark,
        phoneInsets: true,
        before: (s) => s.settings.stylusOnly = true,
      );
      final pen = await tester.startGesture(const Offset(120, 520), kind: PointerDeviceKind.stylus);
      for (var i = 1; i <= 10; i++) {
        await pen.moveTo(Offset(120 + i * 10.0, 520 + (i.isEven ? 6 : -6)));
      }
      await pen.up();
      await tester.pump(TipsController.calmFor); // The tip waits for the pen to rest.
      await settle(tester);
      await shoot(tester, 'e_tip_pen_button_phone_dark');
      await tester.pump(const Duration(seconds: 11));
      await settle(tester);
    });
  });

  // 10. Editor dialogs.
  for (final screen in _screens) {
    for (final mode in modes) {
      final shot = '${screen.name}_${mode.name}';
      testWidgets('e_dialogs $shot', (tester) async {
        await guardOverflows('e_dialogs_$shot', () async {
          await _open(tester, screen, mode);
          await _rename(tester);
          await shoot(tester, 'e_dialog_rename_$shot');
          await _cancel(tester);
          await _insertPageWithTemplate(tester);
          await shoot(tester, 'e_dialog_add_page_template_$shot');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await settle(tester);
          await _menu(tester, ['Page', 'Change template…']);
          await shoot(tester, 'e_dialog_change_template_$shot');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await settle(tester);
          await _menu(tester, ['Page', 'Bookmark page']);
          await shoot(tester, 'e_bookmarked_$shot');
        });
      });
    }
  }

  testWidgets('e_dialogs phone large text', (tester) async {
    await guardOverflows('e_dialogs_phone_large_text', () async {
      await _open(tester, phoneScreen, ThemeMode.light);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      await settle(tester);
      await _rename(tester);
      await shoot(tester, 'e_dialog_rename_phone_large_text');
      await _cancel(tester);
      await _insertPageWithTemplate(tester);
      await shoot(tester, 'e_dialog_add_page_template_phone_large_text');
    });
  });

  for (final mode in modes) {
    testWidgets('e_dialog canvas background ${mode.name}', (tester) async {
      await guardOverflows('e_dialog_background_${mode.name}', () async {
        final s = bareServices();
        await pumpNotebook(tester, s, whiteboard(s), screen: desktopScreen, mode: mode);
        await _menu(tester, ['Background…']);
        await shoot(tester, 'e_dialog_canvas_background_desktop_${mode.name}');
      });
    });
  }

  // 11. Error states: a planner link to a missing page; a PDF background
  // whose file is not on this device.
  for (final screen in [phoneScreen, tabletScreen]) {
    for (final mode in modes) {
      final shot = '${screen.name}_${mode.name}';
      testWidgets('e_missing $shot', (tester) async {
        await guardOverflows('e_missing_$shot', () async {
          final s = bareServices()..preferences.stylusOnly = true;
          final oct = DateTime.utc(2026, 10, 1);
          final nb = s.notebooks.create(
            title: 'Planner 2026',
            kind: NotebookKind.paged,
            paper: PaperStyle.blank,
            coverColor: 0xFF0B7285,
            papers: [Paper.planner(PaperStyle.monthlyCalendar, oct)],
          );
          final first = s.pages.pagesOf(nb.id).single;
          s.pages.insertPages(nb.id, [
            (
              size: first.size,
              paper: const Paper(PaperStyle.blank),
              color: PaperColor.white,
              background: PageBackground.pdf(blob: 'ab' * 32, pageIndex: 2),
            ),
          ], after: first);
          await pumpNotebook(tester, s, nb, screen: screen, mode: mode);
          final day = Paper.planner(PaperStyle.dailyPlanner, DateTime.utc(2026, 10, 14));
          await tester.tapAt(_linkOn(tester, 0, day));
          await settle(tester);
          expect(find.textContaining('has no page for'), findsOneWidget);
          await shoot(tester, 'e_missing_planner_page_$shot');
          ScaffoldMessenger.of(tester.element(find.byType(EditorScreen))).removeCurrentSnackBar();
          final doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
          doc.goToPage(1);
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
          await settle(tester);
          await shoot(tester, 'e_missing_pdf_background_$shot');
        });
      });
    }
  }
}
