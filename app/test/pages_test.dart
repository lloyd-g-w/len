import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/page_order.dart';
import 'package:len/data/page_repository.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';

Stroke _stroke(String id, String surface) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.pen,
  color: 0xFF000000,
  width: 2,
  points: const [StrokePoint(10, 10, 0.5), StrokePoint(40, 30, 0.5)],
  createdAt: 1,
);

void main() {
  group('PageOrder', () {
    test('between', () {
      expect(PageOrder.between(null, null), 1);
      expect(PageOrder.between(3, null), 4);
      expect(PageOrder.between(null, 3), 2);
      expect(PageOrder.between(1, 2), 1.5);
      expect(PageOrder.between(1, 1 + 1e-12), isNull);
    });

    test('spread fits keys strictly inside the gap', () {
      final keys = PageOrder.spread(1, 2, 3)!;
      expect(keys, [1.25, 1.5, 1.75]);
      expect(PageOrder.spread(5, null, 2), [6, 7]);
      expect(PageOrder.spread(null, 1, 2)!.every((k) => k < 1), isTrue);
      expect(PageOrder.spread(1, 1 + 1e-10, 5), isNull);
    });

    test('forMove computes a key between the new neighbours', () {
      final keys = [1.0, 2.0, 3.0, 4.0];
      expect(PageOrder.forMove(keys, 0, 3), 5); // to the end
      expect(PageOrder.forMove(keys, 3, 0), 0); // to the start
      expect(PageOrder.forMove(keys, 0, 1), 2.5); // after the old second
      expect(PageOrder.forMove(keys, 3, 1), 1.5);
    });
  });

  group('PageRepository', () {
    late AppServices s;
    late Notebook nb;
    late PageRepository pages;

    setUp(() {
      s = AppServices.create(AppDatabase.inMemory());
      pages = s.pages;
      nb = s.notebooks.create(
        title: 'N',
        kind: NotebookKind.paged,
        paper: PaperStyle.dotted,
        coverColor: 0,
        firstPage: const PageTemplate(
          style: PaperStyle.cornell,
          color: PaperColor.cream,
          format: PageFormat.letter,
          orientation: PageOrientation.landscape,
        ),
      );
    });
    tearDown(() => s.dispose());

    List<String> ids() => pages.pagesOf(nb.id).map((p) => p.id).toList();

    test('the first page follows the chosen template', () {
      final page = pages.pagesOf(nb.id).single;
      expect(page.paper, PaperStyle.cornell);
      expect(page.paperColor, PaperColor.cream);
      expect(page.size, const Size(1056, 816));
      expect(page.template.orientation, PageOrientation.landscape);
    });

    test('insert before and after', () {
      final first = pages.pagesOf(nb.id).single;
      final after = pages.addPage(nb.id, template: const PageTemplate(), after: first);
      final before = pages.addPage(nb.id, template: const PageTemplate(), before: first);
      final middle = pages.addPage(nb.id, template: const PageTemplate(), before: after);
      expect(ids(), [before.id, first.id, middle.id, after.id]);
    });

    test('move reorders and renumbers when keys run out', () {
      final a = pages.pagesOf(nb.id).single;
      final b = pages.addPage(nb.id, template: const PageTemplate());
      final c = pages.addPage(nb.id, template: const PageTemplate());
      pages.move(c, 0);
      expect(ids(), [c.id, a.id, b.id]);
      // Repeatedly moving into the same gap exhausts it; order stays right.
      for (var i = 0; i < 80; i++) {
        final list = pages.pagesOf(nb.id);
        pages.move(list.last, 1);
      }
      expect(pages.pagesOf(nb.id), hasLength(3));
      expect(ids().toSet(), {a.id, b.id, c.id});
    });

    test('paper, bookmarks, delete and restore are synced edits', () {
      final page = pages.pagesOf(nb.id).single;
      for (final st in s.sync.engine.stores) {
        st.markClean([for (final r in st.dirtyRecords(1000)) (id: r.id, updatedAt: r.updatedAt)]);
      }
      pages.setPaper([page.id], style: PaperStyle.music, color: PaperColor.dark);
      pages.setBookmarked(page.id, true);
      final updated = pages.get(page.id)!;
      expect(updated.paper, PaperStyle.music);
      expect(updated.paperColor, PaperColor.dark);
      expect(updated.bookmarked, isTrue);
      final record = pages.dirtyRecords(10).single;
      expect(record.data!['bookmarked'], true);
      expect(record.data!['paperColor'], 'dark');

      pages.delete(page.id);
      expect(pages.pagesOf(nb.id), isEmpty);
      pages.restore(page.id);
      expect(pages.pagesOf(nb.id).single.bookmarked, isTrue);
    });

    test('remote values from newer versions survive local edits', () {
      final page = pages.pagesOf(nb.id).single;
      pages.applyRemote(
        SyncRecord(
          collection: 'pages',
          id: page.id,
          updatedAt: DateTime(2100).millisecondsSinceEpoch,
          deviceId: 'other',
          deleted: false,
          data: {
            'notebookId': nb.id,
            'sortKey': 1,
            'width': 500,
            'height': 600,
            'paper': 'hexagons',
            'background': {'type': 'video', 'url': 'x'},
          },
        ),
      );
      final local = pages.get(page.id)!;
      expect(local.paper, PaperStyle.blank); // Unknown → blank …
      expect(local.paperColor, PaperColor.white); // … missing → defaults.
      expect(local.background, isNull);
      pages.setBookmarked(page.id, true);
      final data = pages.dirtyRecords(10).single.data!;
      expect(data['paper'], 'hexagons'); // … but kept for newer devices.
      expect(data['background'], {'type': 'video', 'url': 'x'});
    });

    test('PDF backgrounds round-trip', () {
      const sha = 'ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12';
      final created = pages.insertPages(nb.id, [
        for (var i = 0; i < 3; i++)
          (
            size: const Size(612, 792),
            paper: PaperStyle.blank,
            color: PaperColor.white,
            background: PageBackground.pdf(blob: sha, pageIndex: i),
          ),
      ]);
      expect(created.map((p) => p.background!.pageIndex), [0, 1, 2]);
      expect(pages.pagesOf(nb.id).skip(1).map((p) => p.background), [
        for (var i = 0; i < 3; i++) PageBackground.pdf(blob: sha, pageIndex: i),
      ]);
      expect(pages.referencedBlobs(), {sha});
      expect(PageBackground.fromJson({'type': 'pdf', 'blob': 'nope', 'page': 0}), isNull);
    });

    test('surface copier duplicates strokes with new ids', () {
      final page = pages.pagesOf(nb.id).single;
      s.strokes.save([_stroke('a', page.id), _stroke('b', page.id)]);
      final copy = pages.addPage(nb.id, template: page.template, after: page);
      final copier = SurfaceCopier(s.strokes);
      expect(copier.copy(from: page.id, to: copy.id), 2);
      final copied = copier.loadAll(copy.id);
      expect(copied, hasLength(2));
      expect(copied.map((st) => st.id).toSet().intersection({'a', 'b'}), isEmpty);
      expect(copied.every((st) => st.surfaceId == copy.id), isTrue);
      expect(copier.loadAll(page.id), hasLength(2));
      expect(
        s.strokes.dirtyRecords(10).where((r) => r.data!['surfaceId'] == copy.id),
        hasLength(2),
      );
    });
  });
}
