import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/document/page_overview.dart';

import 'screenshot_harness.dart';

/// The page overview of a 9-page notebook with ink and bookmarks.
void main() {
  setUpAll(loadRealFonts);

  Widget overview(AppServices s, String notebookId) => PageOverview(
    currentPage: 1,
    copier: SurfaceCopier(s.strokes, elements: s.elements),
    handlers: OverviewHandlers(
      load: () => s.pages.pagesOf(notebookId),
      command: (context, command, page) async {},
      move: (page, to) => s.pages.move(page, to),
    ),
  );

  for (final (name, size, dpr) in [
    ('phone', const Size(390, 844), 2.0),
    ('tablet_portrait', const Size(800, 1280), 1.0),
    ('desktop', const Size(1440, 900), 1.0),
  ]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('overview $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final s = seededServices();
        addTearDown(s.dispose);
        final nb = s.notebooks.list().firstWhere((n) => n.title == 'Physics — Mechanics');
        for (var i = 0; i < 8; i++) {
          s.pages.addPage(
            nb.id,
            template: PageTemplate(
              style: i.isEven ? PaperStyle.collegeRuled : PaperStyle.gridLarge,
              color: i == 5 ? PaperColor.cream : PaperColor.white,
            ),
          );
        }
        final pages = s.pages.pagesOf(nb.id);
        s.pages.setBookmarked(pages[3].id, true);
        s.strokes.save(handwriting(pages[2].id, ShotClock('a'), lines: 5, canvas: false));
        s.strokes.save(handwriting(pages[5].id, ShotClock('b'), lines: 12, canvas: false));
        await pumpApp(tester, s, overview(s, nb.id), mode: mode);
        expect(tester.takeException(), isNull);
        await shoot(tester, 'overview_${name}_${mode.name}');
        await tester.tap(find.text('Select'));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('page-tile-2')));
        await tester.tap(find.byKey(const ValueKey('page-tile-3')));
        await settle(tester);
        expect(find.text('2 selected'), findsOneWidget);
        await shoot(tester, 'overview_select_${name}_${mode.name}');
        expect(nb.kind, NotebookKind.paged);
      });
    }
  }
}
