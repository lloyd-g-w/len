import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/link_target.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';

import 'data_test.dart' show FakeClock;

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
