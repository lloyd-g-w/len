import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/document/document_surfaces.dart';
import 'package:len/features/editor/document/page_models.dart';
import 'package:len/ink/undo_history.dart';

Stroke _stroke(String id, String surface) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF000000,
  width: 2,
  points: const [StrokePoint(10, 10, 0.5), StrokePoint(40, 30, 0.5)],
  createdAt: 1,
);

void main() {
  late DocumentSurfaces surfaces;

  setUp(() {
    final db = AppDatabase.inMemory();
    surfaces = DocumentSurfaces(StrokeRepository(db, deviceId: 'd'));
    addTearDown(() {
      surfaces.dispose();
      db.close();
    });
  });

  Set<String> ids(String page) => surfaces
      .surfaceOf(page)
      .model
      .strokesNear(const Rect.fromLTWH(0, 0, 100, 100))
      .map((s) => s.id)
      .toSet();

  /// The stroke ids on pages A and B, e.g. `a1,a2|b1`.
  String state() => [
    for (final p in ['A', 'B']) (ids(p).toList()..sort()).join(','),
  ].join('|');

  test('notebook-wide undo and redo follow the order of edits across pages', () {
    final a = surfaces.surfaceOf('A').model;
    final b = surfaces.surfaceOf('B').model;
    a.addStroke(_stroke('a1', 'A'));
    b.addStroke(_stroke('b1', 'B'));
    a.addStroke(_stroke('a2', 'A'));

    surfaces.undo();
    expect(state(), 'a1|b1');
    surfaces.undo();
    expect(state(), 'a1|', reason: 'B was edited before a2');
    surfaces.undo();
    expect(state(), '|');
    expect(surfaces.canUndo, isFalse);

    surfaces.redo();
    expect(state(), 'a1|');
    surfaces.redo();
    expect(state(), 'a1|b1');
    surfaces.redo();
    expect(state(), 'a1,a2|b1');
    expect(surfaces.canRedo, isFalse);
  });

  test('edits merged into the previous step are one notebook-wide step', () {
    final a = surfaces.surfaceOf('A').model;
    final b = surfaces.surfaceOf('B').model;
    a.addStroke(_stroke('a1', 'A'));
    b.addStroke(_stroke('b1', 'B'));
    b.commit(InkEdit(added: [_stroke('b2', 'B')]), merge: true);

    surfaces.undo();
    expect(state(), 'a1|');
    surfaces.undo();
    expect(ids('A'), isEmpty);
  });

  test('two views share page models and one notebook-wide undo', () {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final repository = StrokeRepository(db, deviceId: 'd');
    final models = PageModels();
    final left = DocumentSurfaces(repository, models: models, keepIdle: 0);
    final right = DocumentSurfaces(repository, models: models, keepIdle: 0);
    addTearDown(() {
      right.dispose();
      models.dispose();
    });
    final a = left.surfaceOf('A').model;
    expect(right.surfaceOf('A').model, same(a));
    a.addStroke(_stroke('a1', 'A'));
    left.surfaceOf('B').model.addStroke(_stroke('b1', 'B'));
    expect(right.canUndo, isTrue);

    // The left view goes: the right one still undoes its edits, on page B
    // too although it never showed that page.
    left.dispose();
    right.undo();
    expect(models.peek('B')!.strokesNear(const Rect.fromLTWH(0, 0, 100, 100)), isEmpty);
    right.undo();
    expect(a.strokesNear(const Rect.fromLTWH(0, 0, 100, 100)), isEmpty);
    expect(right.canUndo, isFalse);

    // Pages deleted: their models go once no view holds them.
    right.retain(const {});
    expect(models.peek('A'), isNull);
    expect(models.peek('B'), isNull);
  });

  test('page edits are steps among the ink; an older one can be taken back alone', () {
    final log = <String>[];
    PageEdit edit(String name) =>
        PageEdit(undo: () => log.add('-$name'), redo: () => log.add('+$name'));
    final template = edit('template');
    surfaces.models.record(template);
    surfaces.surfaceOf('A').model.addStroke(_stroke('a1', 'A'));
    final bookmark = edit('bookmark');
    surfaces.models.record(bookmark);

    surfaces.undo();
    expect(log, ['-bookmark']);
    surfaces.redo();
    expect(log, ['-bookmark', '+bookmark']);

    // A snack bar's Undo for the template, pressed after later edits.
    expect(surfaces.models.undoEdit(template), isTrue);
    expect(log.last, '-template');
    expect(surfaces.models.undoEdit(template), isFalse, reason: 'only once');
    surfaces.undo();
    surfaces.undo();
    expect(log.last, '-bookmark');
    expect(state(), '|');
    expect(surfaces.canUndo, isFalse);
  });
}
