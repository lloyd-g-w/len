import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/document/document_surfaces.dart';
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
}
