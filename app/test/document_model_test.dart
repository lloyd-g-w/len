import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/link_target.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';

import 'package:len/features/editor/document/page_actions.dart';

import 'data_test.dart' show FakeClock, stroke;
import 'elements_test.dart' show textBox;

/// Adversarial tests of the document model: pages, duplication, links.
void main() {
  late AppServices s;
  late FakeClock clock;

  setUp(() {
    clock = FakeClock();
    s = AppServices.create(AppDatabase.inMemory(), clock: clock);
  });
  tearDown(() => s.dispose());

  Notebook paged([String title = 'N']) => s.notebooks.create(
    title: title,
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0,
  );

  group('pages', () {
    test('inserting after a page renumbered meanwhile lands right after it', () {
      final nb = paged();
      final a = s.pages.pagesOf(nb.id).single;
      final b = s.pages.addPage(nb.id); // The editor holds b with key 2.
      // Exhausting the gap after a renumbers the notebook.
      for (var i = 0; i < 60; i++) {
        s.pages.addPage(nb.id, after: a);
      }
      expect(s.pages.get(b.id)!.sortKey, isNot(b.sortKey));
      final added = s.pages.addPage(nb.id, after: b);
      expect(s.pages.pagesOf(nb.id).map((p) => p.id).skip(61), [b.id, added.id]);
    });

    test('inserting after a page moved by someone else follows its new place', () {
      final nb = paged();
      final a = s.pages.pagesOf(nb.id).single;
      final b = s.pages.addPage(nb.id);
      final c = s.pages.addPage(nb.id);
      s.pages.move(a, 1); // b, a, c — the editor still holds a's old key.
      final added = s.pages.addPage(nb.id, after: a);
      expect(s.pages.pagesOf(nb.id).map((p) => p.id), [b.id, a.id, added.id, c.id]);
    });
  });

  group('page actions', () {
    test('toggling a stale page copy toggles what is stored', () {
      final nb = paged();
      final page = s.pages.pagesOf(nb.id).single;
      final actions = PageActions(s, nb.id);
      actions.toggleBookmark(page); // Bookmarked (in another view, say).
      actions.toggleBookmark(page); // This view still holds the unbookmarked page.
      expect(s.pages.get(page.id)!.bookmarked, isFalse);
    });

    test('delete then restore brings back the page in place with ink and text', () {
      final nb = paged();
      final actions = PageActions(s, nb.id);
      final first = s.pages.pagesOf(nb.id).single;
      final middle = actions.add(PageActions.blankAfter(first), after: first);
      actions.add(PageActions.blankAfter(middle), after: middle);
      s.strokes.save([stroke('ink', const Offset(10, 10), surface: middle.id)]);
      s.elements.save([textBox('box', const Offset(20, 20), surface: middle.id)]);
      final order = actions.pages.map((p) => p.id).toList();

      final deleted = actions.delete(middle);
      expect(actions.pages, hasLength(2));
      final content = SurfaceCopier(s.strokes, elements: s.elements);
      expect(content.loadAll(middle.id), isEmpty);
      expect(content.loadAllElements(middle.id), isEmpty);

      actions.restore(deleted);
      expect(actions.pages.map((p) => p.id), order);
      expect(content.loadAll(middle.id).single.id, 'ink');
      expect(content.loadAllElements(middle.id).single.id, 'box');
      // Every restored row goes out to other devices again.
      final dirty = {for (final r in s.strokes.dirtyRecords(100)) r.id: r.deleted};
      expect(dirty['ink'], isFalse);
    });

    test('a duplicated page copies ink and text under new ids, right after it', () {
      final nb = paged();
      final actions = PageActions(s, nb.id);
      final first = s.pages.pagesOf(nb.id).single;
      final last = actions.add(PageActions.blankAfter(first));
      s.strokes.save([stroke('ink', const Offset(10, 10), surface: first.id)]);
      s.elements.save([textBox('box', const Offset(20, 20), surface: first.id)]);
      final copy = actions.duplicate(first);
      expect(actions.pages.map((p) => p.id), [first.id, copy.id, last.id]);
      final content = SurfaceCopier(s.strokes, elements: s.elements);
      final ink = content.loadAll(copy.id).single;
      expect(ink.id, isNot('ink'));
      expect(ink.points, content.loadAll(first.id).single.points);
      expect(content.loadAllElements(copy.id).single.id, isNot('box'));
    });
  });

  group('duplicate notebook', () {
    test('links to its own pages lead to the copy, others stay', () {
      final nb = paged('Source');
      final other = paged('Other');
      final p1 = s.pages.pagesOf(nb.id).single;
      final p2 = s.pages.addPage(nb.id);
      final elsewhere = s.pages.pagesOf(other.id).single;
      s.elements.save([
        LinkElements.create(
          id: 'inside',
          surfaceId: p1.id,
          rect: const Rect.fromLTWH(10, 10, 50, 20),
          target: PageLinkTarget(notebookId: nb.id, pageId: p2.id),
          createdAt: 1,
          z: -1,
        ),
        LinkElements.create(
          id: 'outside',
          surfaceId: p2.id,
          rect: const Rect.fromLTWH(10, 10, 50, 20),
          target: PageLinkTarget(notebookId: other.id, pageId: elsewhere.id),
          createdAt: 1,
          z: -1,
        ),
        LinkElements.create(
          id: 'web',
          surfaceId: p2.id,
          rect: const Rect.fromLTWH(10, 100, 50, 20),
          target: UrlLinkTarget.parse('example.com')!,
          createdAt: 1,
          z: -1,
        ),
      ]);

      final copy = s.notebooks.duplicate(nb.id)!;
      final copied = s.pages.pagesOf(copy.id);
      final content = SurfaceCopier(s.strokes, elements: s.elements);
      final first = content.loadAllElements(copied[0].id).single;
      expect(
        LinkElements.targetOf(first),
        PageLinkTarget(notebookId: copy.id, pageId: copied[1].id),
      );
      final second = {
        for (final e in content.loadAllElements(copied[1].id)) LinkElements.targetOf(e),
      };
      expect(second, {
        PageLinkTarget(notebookId: other.id, pageId: elsewhere.id),
        UrlLinkTarget.parse('example.com'),
      });
      // The source keeps its links.
      expect(
        LinkElements.targetOf(content.loadAllElements(p1.id).single),
        PageLinkTarget(notebookId: nb.id, pageId: p2.id),
      );
    });
  });
}
