@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/sidebar/page_sidebar.dart';

import 'editor_screenshot_test.dart' show desktop, pumpEditor, tablet;
import 'screenshot_harness.dart';

/// The page sidebar beside the seeded "Physics" notebook (handwriting,
/// eight pages, one bookmarked, the second on screen) on a tablet held
/// sideways and a desktop, light and dark; and the overview offering it.
void main() {
  setUpAll(loadRealFonts);

  void seed(AppServices s) {
    final physics = s.notebooks.list().firstWhere((n) => n.title.startsWith('Physics'));
    for (var i = 0; i < 5; i++) {
      s.pages.addPage(
        physics.id,
        paper: Paper(i.isEven ? PaperStyle.gridSmall : PaperStyle.collegeRuled),
      );
    }
    final pages = s.pages.pagesOf(physics.id);
    s.pages.setBookmarked(pages[2].id, true);
    s.strokes.save(handwriting(pages[4].id, ShotClock('sidebar'), lines: 8, canvas: false));
    s.settings.setPageSidebar(physics.id, true);
  }

  for (final (name, size) in [('tablet', tablet), ('desktop', desktop)]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('page sidebar $name ${mode.name}', (tester) async {
        await pumpEditor(tester, size: size, mode: mode, before: seed);
        expect(find.byType(PageSidebar), findsOneWidget);
        // The second page on screen: its number marked.
        await tester.tap(find.text('2').last);
        await settle(tester);
        expect(tester.takeException(), isNull);
        await shoot(tester, 'page_sidebar_${name}_${mode.name}');
        if (name != 'tablet' || mode != ThemeMode.light) return;
        // At the end of the column: Add page.
        await tester.drag(find.text('3').last, const Offset(0, -2000));
        await settle(tester);
        expect(find.text('Add page'), findsOneWidget);
        await shoot(tester, 'page_sidebar_end_${name}_${mode.name}');
      });
    }
  }

  testWidgets('the overview offers the pages beside the page', (tester) async {
    await pumpEditor(
      tester,
      size: desktop,
      before: (s) {
        seed(s);
        s.settings.setPageSidebar(
          s.notebooks.list().firstWhere((n) => n.title.startsWith('Physics')).id,
          false,
        );
      },
    );
    expect(find.byType(PageSidebar), findsNothing);
    await tester.tap(find.byTooltip('All pages'));
    await settle(tester);
    expect(find.text('Show beside the page'), findsOneWidget);
    await shoot(tester, 'page_sidebar_overview_desktop_light');
  });
}
