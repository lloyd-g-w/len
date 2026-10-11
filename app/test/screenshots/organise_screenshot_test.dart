import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/link_target.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/tag.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/tools/content_layer.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/library/notebook_card.dart';
import 'package:len/features/stickers/builtin_stickers.dart';
import 'package:len/ui/app_theme.dart';

import 'screenshot_harness.dart';

/// Organisation features with real fonts: tags in the library (sidebar,
/// chips, picker, manager), the editor's outline panel, links and the
/// sticker panel, on desktop / tablet and phone, light and dark.
void main() {
  setUpAll(loadRealFonts);

  const phone = ('phone', Size(390, 844), 2.0);
  const desktop = ('desktop', Size(1440, 900), 1.0);
  const tablet = ('tablet', Size(1280, 800), 1.0);

  /// The seeded library with tags on a few notebooks.
  AppServices tagged() {
    final s = seededServices();
    final notebooks = {for (final n in s.notebooks.list()) n.title: n.id};
    final school = s.tags.create(name: 'School', color: Palette.covers[0]);
    final urgent = s.tags.create(name: 'Urgent', color: Palette.covers[3]);
    final home = s.tags.create(name: 'Home', color: Palette.covers[1]);
    void tag(String title, Tag t) =>
        s.tags.taggings.set(t.id, notebooks[title]!, TagTarget.notebook, on: true);
    tag('Physics — Mechanics', school);
    tag('Physics — Mechanics', urgent);
    tag('Spanish vocabulary', school);
    tag('Recipes', home);
    tag('Travel plans', home);
    tag('Meeting notes', urgent);
    return s;
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, warnIfMissed: false);
    await settle(tester);
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final (name, size, dpr) in [desktop, phone]) {
      testWidgets('library tags $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final s = tagged();
        addTearDown(s.dispose);
        await pumpApp(tester, s, const LibraryScreen(), mode: mode);
        await shoot(tester, 'o_library_tags_${name}_${mode.name}');

        if (name == 'desktop') {
          await tap(tester, find.byKey(ValueKey('sidebar-tag-${s.tags.byName('school')!.id}')));
        } else {
          await tap(tester, find.byKey(ValueKey('tag-chip-${s.tags.byName('school')!.id}')));
        }
        await shoot(tester, 'o_library_tag_filter_${name}_${mode.name}');

        await tap(
          tester,
          find
              .descendant(
                of: find.ancestor(
                  of: find.text('Physics — Mechanics'),
                  matching: find.byType(NotebookCard),
                ),
                matching: find.byTooltip('More'),
              )
              .first,
        );
        await tap(tester, find.text('Tags…'));
        await shoot(tester, 'o_tag_picker_${name}_${mode.name}');
        await tester.binding.handlePopRoute();
        await settle(tester);

        await tap(tester, find.byTooltip('Manage tags').first);
        await shoot(tester, 'o_tag_manager_${name}_${mode.name}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    for (final (name, size, dpr) in [tablet, phone]) {
      testWidgets('editor outline, links, stickers $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final s = seededServices();
        addTearDown(s.dispose);
        final nb = s.notebooks.list().firstWhere((n) => n.title == 'Physics — Mechanics');
        s.pages.addPage(nb.id, template: const PageTemplate(paper: Paper(PaperStyle.wideRuled)));
        s.pages.addPage(nb.id, template: const PageTemplate(paper: Paper(PaperStyle.wideRuled)));
        final pages = s.pages.pagesOf(nb.id);
        final intro = s.outline.add(notebookId: nb.id, pageId: pages[0].id, title: 'Mechanics');
        s.outline.add(
          notebookId: nb.id,
          pageId: pages[0].id,
          title: 'Newton’s laws',
          parentId: intro.id,
        );
        s.outline.add(
          notebookId: nb.id,
          pageId: pages[1].id,
          title: 'Momentum and impulse',
          parentId: intro.id,
        );
        s.outline.add(notebookId: nb.id, pageId: pages[2].id, title: 'Exercises');
        final ink = SurfaceCopier(s.strokes).loadAll(pages[0].id);
        final line = ink.take(4).map((x) => x.bounds).reduce((a, b) => a.expandToInclude(b));
        s.elements.save([
          LinkElements.create(
            id: 'link',
            surfaceId: pages[0].id,
            rect: line.inflate(4),
            target: PageLinkTarget(notebookId: nb.id, pageId: pages[2].id),
            createdAt: 1,
            z: -1,
          ),
        ]);
        s.stickers.create(
          name: 'Heart',
          category: 'Favourites',
          content: BuiltinStickers.all.firstWhere((x) => x.name == 'Heart').content,
        );
        await pumpApp(tester, s, EditorScreen(notebook: nb), mode: mode);
        await shoot(tester, 'o_editor_link_${name}_${mode.name}');

        await tap(tester, find.byTooltip('More options'));
        await tap(tester, find.text('Outline'));
        await shoot(tester, 'o_outline_panel_${name}_${mode.name}');
        await tester.binding.handlePopRoute();
        await settle(tester);

        await tap(tester, find.byTooltip('More options'));
        await tap(tester, find.text('Stickers'));
        await shoot(tester, 'o_sticker_panel_${name}_${mode.name}');
        await tap(tester, find.byKey(const ValueKey('sticker-category-Callouts')));
        await shoot(tester, 'o_sticker_callouts_${name}_${mode.name}');
        await tap(tester, find.byTooltip('Close stickers'));

        // A lasso selection's menu with Link… and Save as sticker….
        final content = tester.widget<ContentLayer>(find.byType(ContentLayer)).content;
        final model = content.selection.model;
        content.selection.select([for (final x in ink.take(4)) ?model.strokeById(x.id)], const []);
        await settle(tester);
        await shoot(tester, 'o_selection_menu_${name}_${mode.name}');
        if (find.byTooltip('Save as sticker…').evaluate().isNotEmpty) {
          await tap(tester, find.byTooltip('Save as sticker…'));
        } else {
          await tap(tester, find.byTooltip('More'));
          await tap(tester, find.text('Save as sticker…'));
        }
        await shoot(tester, 'o_save_sticker_${name}_${mode.name}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('outline add dialog and link picker (tablet light)', (tester) async {
    setWindow(tester, tablet.$2);
    final s = seededServices();
    addTearDown(s.dispose);
    final nb = s.notebooks.list().firstWhere((n) => n.title == 'Physics — Mechanics');
    s.pages.addPage(nb.id, template: const PageTemplate(paper: Paper(PaperStyle.wideRuled)));
    s.outline.add(notebookId: nb.id, pageId: s.pages.pagesOf(nb.id).first.id, title: 'Start');
    await pumpApp(tester, s, EditorScreen(notebook: nb));
    await tap(tester, find.byTooltip('More options'));
    await tap(tester, find.text('Page'));
    await tap(tester, find.text('Add page to outline…'));
    await shoot(tester, 'o_outline_add_tablet_light');
    await tester.binding.handlePopRoute();
    await settle(tester);

    final content = tester.widget<ContentLayer>(find.byType(ContentLayer)).content;
    final model = content.selection.model;
    final first = SurfaceCopier(s.strokes).loadAll(s.pages.pagesOf(nb.id).first.id).first;
    content.selection.select([?model.strokeById(first.id)], const []);
    await settle(tester);
    await tap(tester, find.byTooltip('Link…'));
    await shoot(tester, 'o_link_menu_tablet_light');
    await tap(tester, find.text('Link to page…'));
    await shoot(tester, 'o_link_page_picker_tablet_light');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
