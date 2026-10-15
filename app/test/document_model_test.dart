import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/link_target.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/notebook_style.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';

import 'package:len/features/editor/document/page_actions.dart';
import 'package:len/ink/pen/eraser_config.dart';
import 'package:len/ink/surface_model.dart';

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

    test('undoing a page deletion after the notebook was deleted revives nothing', () {
      final nb = paged();
      final actions = PageActions(s, nb.id);
      final first = s.pages.pagesOf(nb.id).single;
      final second = actions.add(PageActions.blankAfter(first));
      s.strokes.save([stroke('ink', const Offset(10, 10), surface: second.id)]);
      final deleted = actions.delete(second);
      s.notebooks.delete(nb.id);
      actions.restore(deleted);
      expect(s.pages.get(second.id), isNull);
      expect(SurfaceCopier(s.strokes).loadAll(second.id), isEmpty);
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

  group('a page added after a slide (UX_AUDIT R18-2)', () {
    /// [n] slides, as an import makes them (no other pages).
    List<NotebookPage> slides(Notebook nb, int n) {
      final fresh = s.pages.pagesOf(nb.id);
      final deck = s.pages.insertPages(nb.id, [
        for (var i = 0; i < n; i++)
          (
            size: const Size(960, 540),
            paper: Paper.blank,
            color: PaperColor.white,
            background: PageBackground.pdf(blob: 'a' * 64, pageIndex: i),
          ),
      ]);
      for (final p in fresh) {
        s.pages.delete(p.id);
      }
      return deck;
    }

    test('is college ruled at the slide’s size', () {
      final nb = paged();
      final actions = PageActions(s, nb.id);
      final deck = slides(nb, 3);
      final spec = actions.blankPageAfter(deck[1]);
      expect(spec.size, const Size(960, 540));
      expect(spec.paper.style, PaperStyle.collegeRuled);
      expect(spec.background, isNull);
    });

    test('takes the default notebook style’s template', () {
      final nb = paged();
      final style = s.notebookStyles.create(
        name: 'Grid',
        choice: const NotebookChoice(
          paper: PaperStyle.gridSmall,
          paperColor: PaperColor.white,
          coverColor: 0,
        ),
      );
      s.notebookStyles.setDefault(style.id, isDefault: true);
      final deck = slides(nb, 2);
      expect(PageActions(s, nb.id).blankPageAfter(deck[0]).paper.style, PaperStyle.gridSmall);
    });

    test('follows the nearest notes page before it', () {
      final nb = paged();
      final actions = PageActions(s, nb.id);
      final deck = slides(nb, 4);
      final notes = actions.add((
        size: const Size(960, 540),
        paper: const Paper(PaperStyle.dotted),
        color: PaperColor.white,
        background: null,
      ), after: deck[0]);
      expect(actions.blankPageAfter(deck[2]).paper.style, PaperStyle.dotted);
      // A notes page after it is copied as ever.
      expect(actions.blankPageAfter(notes).paper.style, PaperStyle.dotted);
    });

    test('a page without a background is copied as before', () {
      final nb = paged();
      final first = s.pages.pagesOf(nb.id).first;
      expect(PageActions(s, nb.id).blankPageAfter(first).paper.style, first.paper.style);
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

  group('pixel eraser', () {
    Stroke long(String id, double y) => Stroke(
      id: id,
      surfaceId: 'canvas',
      tool: InkTool.ballpoint,
      color: 0xFF000000,
      width: 3,
      points: [for (var x = 0.0; x <= 400; x += 4) StrokePoint(x, y, 0.5)],
      createdAt: 7,
    );

    Map<String, List<StrokePoint>> stored() => {
      for (final st in SurfaceCopier(s.strokes).loadAll('canvas')) st.id: st.points,
    };

    // As stored: float32 coordinates.
    Map<String, List<StrokePoint>> shown(SurfaceModel model) => {
      for (final st in model.strokesNear(const Rect.fromLTRB(-100, -100, 600, 600)))
        st.id: [for (final p in st.points) StrokePoint(_f32(p.x), _f32(p.y), _f32(p.pressure))],
    };

    test('one drag cutting and re-cutting ink undoes and redoes exactly', () {
      final model = SurfaceModel(surfaceId: 'canvas', repository: s.strokes, clock: clock)
        ..ensureLoaded(const Rect.fromLTRB(0, 0, 500, 500));
      model.addStroke(long('a', 50));
      model.addStroke(long('b', 60));
      final before = stored();

      // A zigzag across both lines, then back over the fragments it cut.
      final sweep = [
        const Offset(100, 0),
        const Offset(110, 120),
        const Offset(200, 0),
        const Offset(210, 120),
        const Offset(105, 55),
        const Offset(300, 55),
      ];
      for (var i = 1; i < sweep.length; i++) {
        model.eraseAlong(sweep[i - 1], sweep[i], 4, continueEdit: i > 1, mode: EraserMode.pixel);
      }
      final after = stored();
      expect(after.length, greaterThan(2));
      expect(after.keys, isNot(contains('a')));
      expect(shown(model), after);
      expect(model.history.recorded, 3); // Two strokes, one erase.

      model.undo();
      expect(stored(), before);
      expect(shown(model), before);
      model.redo();
      expect(stored(), after);
      expect(shown(model), after);
      // Fragments keep the stroke's time (paint order, audio replay).
      expect(SurfaceCopier(s.strokes).loadAll('canvas').map((st) => st.createdAt).toSet(), {7});
      model.dispose();

      // As after a restart.
      final reopened = SurfaceModel(surfaceId: 'canvas', repository: s.strokes)
        ..ensureLoaded(const Rect.fromLTRB(0, 0, 500, 500));
      expect(shown(reopened), after);
      reopened.dispose();
    });
  });
}

double _f32(double v) => (Float32List(1)..[0] = v)[0];
