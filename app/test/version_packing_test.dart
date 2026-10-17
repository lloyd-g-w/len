import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/versions/versions.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';

Stroke _ink(String id, String surface, int createdAt) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF102030,
  width: 3,
  points: [StrokePoint(createdAt.toDouble(), 10, 0.5), StrokePoint(createdAt + 20.0, 30, 0.5)],
  createdAt: createdAt,
);

/// Packing for versions (docs/PERFORMANCE.md, round 13): runs packed
/// before are found again by what is in them, a surface changing while it
/// is packed is packed again, and a held recorder waits.
void main() {
  late AppServices s;
  var held = false;
  void Function()? onHold;
  late Versions versions;

  setUp(() {
    s = AppServices.create(AppDatabase.inMemory());
    held = false;
    onHold = null;
    versions = Versions(
      repositories: s.sync.engine.repositories,
      blobs: s.blobs,
      deviceName: 'Test',
      hold: () {
        onHold?.call();
        return held;
      },
    );
  });
  tearDown(() => s.dispose());

  Notebook canvas() => s.notebooks.create(
    title: 'Board',
    kind: NotebookKind.canvas,
    paper: PaperStyle.blank,
    coverColor: 1,
  );

  int blobCount() => s.database.db.select('SELECT COUNT(*) AS n FROM blobs').first['n'] as int;

  Future<Set<String>> strokesIn(NotebookVersion v, String surface) async {
    final body = await versions.content.body(v);
    final content = await versions.content.load(body.canvas!, surface);
    return {for (final st in content.strokes) st.id};
  }

  test('a version after one stroke packs one run; packs match packing afresh', () async {
    final n = canvas();
    s.strokes.save([for (var i = 0; i < 600; i++) _ink('s$i', n.id, i)]);
    final v1 = (await versions.record(n.id))!;
    final packs1 = (await versions.content.body(v1)).canvas!.ink;
    expect(packs1.length, greaterThan(5));
    s.strokes.save([_ink('late', n.id, 1000)]);
    final before = blobCount();
    final v2 = (await versions.record(n.id))!;
    expect(blobCount() - before, 2, reason: 'the last pack and the table');
    final packs2 = (await versions.content.body(v2)).canvas!.ink;
    expect(packs2.take(packs1.length - 1), packs1.take(packs1.length - 1));
    expect(v2.summary.strokesAdded, 1);
    expect(await strokesIn(v2, n.id), {for (var i = 0; i < 600; i++) 's$i', 'late'});
    // Without the caches, the same packs.
    s.database.db.execute('DELETE FROM version_runs');
    s.database.db.execute('DELETE FROM version_packs');
    expect((await versions.snapshots.pack(n.id)).surface.ink, packs2);
  });

  test('an element edited in place is packed again', () async {
    final n = canvas();
    final box = SurfaceElement(
      id: 'box',
      surfaceId: n.id,
      type: 'text',
      rect: const Rect.fromLTWH(0, 0, 100, 40),
      z: 1,
      createdAt: 1,
      data: const TextData(text: 'one').toJson(),
    );
    s.elements.save([box]);
    final v1 = (await versions.record(n.id))!;
    s.elements.save([box.copyWith(data: const TextData(text: 'two').toJson())]);
    final v2 = (await versions.record(n.id))!;
    final b1 = (await versions.content.body(v1)).canvas!;
    final b2 = (await versions.content.body(v2)).canvas!;
    expect(b2.items, isNot(b1.items));
    final content = await versions.content.load(b2, n.id);
    expect(TextData.fromJson(content.elements.single.data).text, 'two');
  });

  test('a stroke erased while the surface is packed: packed again, without it', () async {
    final n = canvas();
    s.strokes.save([for (var i = 0; i < 300; i++) _ink('s$i', n.id, i)]);
    var calls = 0;
    onHold = () {
      // After the mark and the ids are read, before the runs are.
      if (++calls == 3) s.strokes.delete(['s0']);
    };
    final v = (await versions.record(n.id))!;
    expect(await strokesIn(v, n.id), {for (var i = 1; i < 300; i++) 's$i'});
    expect(v.summary.strokes, 299);
  });

  test('held (a pointer down), a version waits', () async {
    final n = canvas();
    s.strokes.save([_ink('a', n.id, 1)]);
    held = true;
    var done = false;
    final made = versions.record(n.id).whenComplete(() => done = true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(done, isFalse);
    s.strokes.save([_ink('b', n.id, 2)]);
    held = false;
    final v = (await made)!;
    expect(await strokesIn(v, n.id), {'a', 'b'});
  });
}
