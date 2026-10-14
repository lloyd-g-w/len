import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/document/page_models.dart';
import 'package:len/ink/geometry/affine.dart';
import 'package:len/ink/pen/eraser_config.dart';
import 'package:len/ink/selection/transform_items.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/undo_history.dart';

import 'data_test.dart' show FakeClock;
import 'elements_test.dart' show textBox;
import 'support/property.dart';

/// What a surface holds: every stroke and element by id (the very objects).
typedef _State = Map<String, Object>;

const _world = Rect.fromLTRB(-2000, -2000, 2000, 2000);

_State _stateOf(SurfaceModel m) => {
  for (final s in m.strokesNear(_world)) s.id: s,
  for (final e in m.elementsNear(_world)) e.id: e,
};

/// What storage holds for [surface], by id, as comparable values.
Map<String, String> _stored(StrokeRepository strokes, ElementRepository elements, String surface) {
  final range = ChunkGrid.rangeFor(_world);
  return {
    for (final s in strokes.loadChunks(surface, strokes.populatedChunks(surface, range)))
      s.id: _key(s),
    for (final e in elements.loadChunks(surface, elements.populatedChunks(surface, range)))
      e.id: _key(e),
  };
}

String _key(Object o) => switch (o) {
  // Stored as 32-bit floats.
  final Stroke s =>
    'stroke ${Float32List.fromList([
      for (final p in s.points) ...[p.x, p.y],
    ])}',
  final SurfaceElement e => 'element ${e.rect} ${TextData.fromJson(e.data).text}',
  _ => '$o',
};

void _expectState(_State actual, _State expected, String when) {
  expect(actual.keys.toSet(), expected.keys.toSet(), reason: when);
  for (final id in expected.keys) {
    expect(identical(actual[id], expected[id]), isTrue, reason: '$when: $id differs');
  }
}

Stroke _line(String id, math.Random r, {String surface = 's'}) {
  final from = Offset(r.nextDouble() * 600, r.nextDouble() * 600);
  final to = from + Offset(r.nextDouble() * 200 - 100, r.nextDouble() * 200 - 100);
  return Stroke(
    id: id,
    surfaceId: surface,
    tool: r.nextDouble() < 0.2 ? InkTool.highlighter : InkTool.ballpoint,
    color: 0xFF000000,
    width: 1 + r.nextDouble() * 6,
    points: [
      for (var i = 0; i < 12; i++)
        StrokePoint(
          from.dx + (to.dx - from.dx) * i / 11,
          from.dy + (to.dy - from.dy) * i / 11,
          0.3 + r.nextDouble() * 0.7,
        ),
    ],
    createdAt: r.nextInt(100),
  );
}

/// Kinds of steps a random session takes.
enum _Op { draw, delete, move, erase, eraseMore, text, retext, untext, undo, redo }

/// Applies one random edit (or undo / redo) to [m]; returns whether it
/// committed an edit, and whether that edit joins the previous step.
({bool committed, bool merged})? _randomOp(SurfaceModel m, math.Random r, FakeClock clock, _Op op) {
  final strokes = m.strokesNear(_world).toList()..sort((a, b) => a.id.compareTo(b.id));
  final elements = m.elementsNear(_world).toList()..sort((a, b) => a.id.compareTo(b.id));
  Stroke? anyStroke() => strokes.isEmpty ? null : strokes[r.nextInt(strokes.length)];
  SurfaceElement? anyElement() => elements.isEmpty ? null : elements[r.nextInt(elements.length)];
  bool commit(InkEdit edit, {bool merge = false}) {
    m.commit(edit, merge: merge);
    return !edit.isEmpty;
  }

  bool erase({required bool more}) {
    final s = anyStroke();
    final at = s?.points[r.nextInt(s.points.length)].offset ?? const Offset(300, 300);
    final to = at + Offset(r.nextDouble() * 40 - 20, r.nextDouble() * 40 - 20);
    return m.eraseAlong(
      at,
      to,
      1 + r.nextDouble() * 10,
      continueEdit: more,
      mode: r.nextBool() ? EraserMode.pixel : EraserMode.stroke,
    );
  }

  switch (op) {
    case _Op.draw:
      final n = 1 + r.nextInt(2);
      return (
        committed: commit(
          InkEdit(
            added: [for (var i = 0; i < n; i++) _line(clock.newId(), r, surface: m.surfaceId)],
          ),
        ),
        merged: false,
      );
    case _Op.delete:
      final s = anyStroke(), e = anyElement();
      return (
        committed: commit(InkEdit(removed: [?s], removedElements: [if (r.nextBool()) ?e])),
        merged: false,
      );
    case _Op.move:
      final picked = {anyStroke(), anyStroke()}.nonNulls.toList();
      final t = Affine.rotation(
        r.nextDouble() * 6,
        pivot: const Offset(300, 300),
      ).then(Affine.translation(Offset(r.nextDouble() * 50, r.nextDouble() * 50)));
      final e = anyElement();
      return (
        committed: commit(
          InkEdit(
            removed: picked,
            added: [for (final s in picked) TransformItems.stroke(s, t, id: clock.newId())],
            removedElements: [?e],
            addedElements: [if (e != null) TransformItems.element(e, t)],
          ),
        ),
        merged: false,
      );
    case _Op.erase:
      return (committed: erase(more: false), merged: false);
    case _Op.eraseMore:
      return (committed: erase(more: true), merged: true);
    case _Op.text:
      final at = Offset(r.nextDouble() * 600, r.nextDouble() * 600);
      return (
        committed: commit(
          InkEdit(
            addedElements: [textBox(clock.newId(), at, text: 'new', surface: m.surfaceId)],
          ),
        ),
        merged: false,
      );
    case _Op.retext:
      final e = anyElement();
      if (e == null) return (committed: false, merged: false);
      // Typing on: may join the previous step.
      final text = TextData(text: 'v${r.nextInt(1000)}');
      final merge = r.nextBool();
      return (
        committed: commit(
          InkEdit(
            removedElements: [e],
            addedElements: [e.copyWith(data: text.toJson())],
          ),
          merge: merge,
        ),
        merged: merge,
      );
    case _Op.untext:
      final e = anyElement();
      return (committed: commit(InkEdit(removedElements: [?e])), merged: false);
    case _Op.undo:
    case _Op.redo:
      return null;
  }
}

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late StrokeRepository strokes;
  late ElementRepository elements;

  setUp(() {
    db = AppDatabase.inMemory();
    clock = FakeClock();
    strokes = StrokeRepository(db, deviceId: 'dev', clock: clock);
    elements = ElementRepository(db, deviceId: 'dev', clock: clock);
  });
  tearDown(() => db.close());

  test('surface undo/redo replays the states a random session went through', () async {
    var surface = 0;
    await forAll((r) => r.nextInt(1 << 30), (seed) {
      final r = math.Random(seed);
      final id = 's${surface++}';
      final m = SurfaceModel(
        surfaceId: id,
        repository: strokes,
        elementRepository: elements,
        clock: clock,
      );
      addTearDown(m.dispose);
      // The reference: the state before each undo step and after each
      // undone one.
      final before = <_State>[], after = <_State>[];
      final start = _stateOf(m);
      for (var i = 0; i < 40; i++) {
        final op = Gens.oneOf(_Op.values)(r);
        final state = _stateOf(m);
        if (op == _Op.undo) {
          expect(m.history.canUndo, before.isNotEmpty);
          m.undo();
          if (before.isNotEmpty) {
            after.add(state);
            _expectState(_stateOf(m), before.removeLast(), 'undo at $i');
          } else {
            _expectState(_stateOf(m), state, 'undo with nothing to undo');
          }
          continue;
        }
        if (op == _Op.redo) {
          expect(m.history.canRedo, after.isNotEmpty);
          m.redo();
          if (after.isNotEmpty) {
            before.add(state);
            _expectState(_stateOf(m), after.removeLast(), 'redo at $i');
          } else {
            _expectState(_stateOf(m), state, 'redo with nothing to redo');
          }
          continue;
        }
        final done = _randomOp(m, r, clock, op)!;
        if (!done.committed) {
          _expectState(_stateOf(m), state, 'no-op $op at $i');
          continue;
        }
        // A new edit drops what could be redone.
        after.clear();
        expect(m.history.canRedo, isFalse);
        if (!done.merged || before.isEmpty) before.add(state);
      }
      final end = _stateOf(m);
      final redoable = after.length;
      // Undo everything: back to the start, in storage too.
      while (m.history.canUndo) {
        m.undo();
      }
      _expectState(_stateOf(m), start, 'undo all');
      expect(_stored(strokes, elements, id), {
        for (final e in _stateOf(m).entries) e.key: _key(e.value),
      });
      // Redo everything: the last state reached, in storage too.
      var redone = 0;
      while (m.history.canRedo) {
        m.redo();
        redone++;
      }
      expect(redone, before.length + redoable);
      final last = after.isEmpty ? end : after.first;
      _expectState(_stateOf(m), last, 'redo all');
      expect(_stored(strokes, elements, id), {
        for (final e in _stateOf(m).entries) e.key: _key(e.value),
      });
    }, runs: 60);
  });

  test('a bounded history undoes its last [limit] steps exactly', () async {
    await forAll(
      (r) => (limit: Gens.intIn(1, 8)(r), steps: Gens.intIn(0, 20)(r), undos: Gens.intIn(0, 25)(r)),
      (c) {
        // A set of ints edited by adding / removing "strokes" named by them.
        final h = UndoHistory(limit: c.limit);
        final states = <Set<String>>[{}];
        var state = <String>{};
        Stroke s(String id) => _line(id, math.Random(id.hashCode));
        final made = <String, Stroke>{};
        for (var i = 0; i < c.steps; i++) {
          final id = 'x$i';
          final drop = state.isNotEmpty && i.isOdd ? state.first : null;
          final edit = InkEdit(added: [made[id] = s(id)], removed: [if (drop != null) made[drop]!]);
          h.record(edit);
          state = {...state.where((x) => x != drop), id};
          states.add(state);
        }
        // Undo applies inverses; it reaches back at most [limit] steps.
        var undone = 0;
        for (var i = 0; i < c.undos; i++) {
          final edit = h.takeUndo();
          if (edit == null) break;
          undone++;
          state = {...state.where((x) => !edit.added.any((a) => a.id == x))};
          state.addAll(edit.removed.map((r) => r.id));
          expect(state, states[states.length - 1 - undone]);
        }
        expect(undone, math.min(c.undos, math.min(c.limit, c.steps)));
        expect(h.canRedo, undone > 0);
      },
      runs: 300,
    );
  });

  test('merging edits equals applying them one after another', () async {
    // Element versions keep their id; strokes are made and erased.
    await forAll((r) => r.nextInt(1 << 30), (seed) {
      final r = math.Random(seed);
      var n = 0;
      // Some ink and text there before.
      final state = <String, Object>{
        for (var k = 0; k < 3; k++) 'old$k': _line('old$k', r),
        for (var k = 3; k < 5; k++) 'old$k': textBox('old$k', Offset.zero),
      };
      void apply(Map<String, Object> s, InkEdit e) {
        for (final x in e.removed) {
          expect(s.remove(x.id), same(x));
        }
        for (final x in e.removedElements) {
          expect(s.remove(x.id), same(x));
        }
        for (final x in e.added) {
          s[x.id] = x;
        }
        for (final x in e.addedElements) {
          s[x.id] = x;
        }
      }

      final start = {...state};
      InkEdit? merged;
      for (var i = 0; i < 12; i++) {
        final strokes = state.values.whereType<Stroke>().toList();
        final els = state.values.whereType<SurfaceElement>().toList();
        final dropS = strokes.isNotEmpty && r.nextBool()
            ? strokes[r.nextInt(strokes.length)]
            : null;
        final el = els.isNotEmpty && r.nextBool() ? els[r.nextInt(els.length)] : null;
        final edit = InkEdit(
          removed: [?dropS],
          added: [for (var k = r.nextInt(3); k > 0; k--) _line('m${n++}', r)],
          removedElements: [?el],
          addedElements: [
            if (el != null && r.nextBool())
              el.copyWith(data: TextData(text: 'v${n++}').toJson())
            else if (r.nextBool())
              textBox('e${n++}', Offset.zero),
          ],
        );
        apply(state, edit);
        merged = merged == null ? edit : merged.mergedWith(edit);
      }
      final replayed = {...start};
      apply(replayed, merged!);
      expect(replayed.keys.toSet(), state.keys.toSet());
      for (final id in state.keys) {
        expect(replayed[id], same(state[id]));
      }
      apply(replayed, merged.inverse);
      expect(replayed, start);
    }, runs: 300);
  });

  test('notebook undo/redo walks back and forth through every page and page edit', () async {
    await forAll((r) => r.nextInt(1 << 30), (seed) {
      final r = math.Random(seed);
      final models = PageModels();
      addTearDown(models.dispose);
      const pages = ['p0', 'p1', 'p2'];
      for (final p in pages) {
        models.acquire(p, () => SurfaceModel(surfaceId: p, repository: strokes, clock: clock));
      }
      // A page-level setting changed by PageEdits (e.g. a template).
      var template = 0;
      Map<String, Object> snapshot() => {
        for (final p in pages) p: _stateOf(models.peek(p)!),
        'template': template,
      };
      void expectSnapshot(Map<String, Object> expected, String when) {
        final actual = snapshot();
        expect(actual['template'], expected['template'], reason: when);
        for (final p in pages) {
          _expectState(actual[p]! as _State, expected[p]! as _State, '$when on $p');
        }
      }

      void draw(String page) =>
          models.peek(page)!.addStroke(_line(clock.newId(), r, surface: page));

      final before = <Map<String, Object>>[], after = <Map<String, Object>>[];
      final start = snapshot();
      String? lastPage;
      for (var i = 0; i < 30; i++) {
        final state = snapshot();
        final page = pages[r.nextInt(pages.length)];
        switch (r.nextInt(7)) {
          case 0 || 1:
            draw(page);
            lastPage = page;
            after.clear();
            before.add(state);
          case 2:
            // Continues the last page's eraser drag (merges into its step).
            final m = models.peek(page)!;
            final victim = m.strokesNear(_world).firstOrNull;
            final erased =
                victim != null &&
                m.eraseAlong(
                  victim.points.first.offset,
                  victim.points.last.offset,
                  2,
                  continueEdit: page == lastPage,
                );
            if (erased) {
              after.clear();
              if (page != lastPage || before.isEmpty) before.add(state);
              lastPage = page;
            }
          case 3:
            models.group(() {
              draw(pages[0]);
              draw(pages[2]);
            });
            lastPage = null;
            after.clear();
            before.add(state);
          case 4:
            final from = template, to = template + 1 + r.nextInt(5);
            template = to;
            models.record(PageEdit(undo: () => template = from, redo: () => template = to));
            lastPage = null;
            after.clear();
            before.add(state);
          case 5:
            expect(models.canUndo, before.isNotEmpty);
            models.undo();
            lastPage = null;
            if (before.isEmpty) continue;
            after.add(state);
            expectSnapshot(before.removeLast(), 'undo at $i');
          case 6:
            expect(models.canRedo, after.isNotEmpty);
            models.redo();
            lastPage = null;
            if (after.isEmpty) continue;
            before.add(state);
            expectSnapshot(after.removeLast(), 'redo at $i');
        }
        expect(models.canRedo, after.isNotEmpty, reason: 'redo after step $i');
      }
      final end = snapshot();
      while (models.canUndo) {
        models.undo();
      }
      expectSnapshot(start, 'undo all');
      while (models.canRedo) {
        models.redo();
      }
      expectSnapshot(after.isNotEmpty ? after.first : end, 'redo all');
    }, runs: 60);
  });
}
