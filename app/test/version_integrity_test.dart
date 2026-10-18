import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/versions/version_restorer.dart';
import 'package:len/data/versions/versions.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';

/// A clock tests move by hand; ids `v0`, `v1`, …
class _Clock extends Clock {
  int now = DateTime.utc(2026, 10, 1, 12).millisecondsSinceEpoch;
  int _ids = 0;

  @override
  int nowMs() => now;

  @override
  String newId() => 'v${_ids++}';
}

Stroke _ink(String id, String surface, int i) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF102030,
  width: 3,
  points: [StrokePoint(i.toDouble(), 10, 0.5), StrokePoint(i + 20.0, 30, 0.5)],
  createdAt: i,
);

/// Versions hold whole states: never half of an edit written in steps,
/// never without what a restore removes.
void main() {
  late _Clock clock;
  late AppServices s;

  setUp(() {
    clock = _Clock();
    s = AppServices.create(AppDatabase.inMemory(), clock: clock);
  });
  tearDown(() => s.dispose());

  String page() {
    final n = s.notebooks.create(
      title: 'Lab',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 1,
    );
    return s.pages.pagesOf(n.id).single.id;
  }

  Future<Set<String>> versionInk(NotebookVersion v, String page) async {
    final body = await s.versions.content.body(v);
    final surface = body.pages.singleWhere((p) => p.id == page).content;
    return s.versions.content.strokeIds(surface);
  }

  test('a version made while an edit is written in steps holds all of it', () async {
    final p = page();
    final notebook = s.pages.notebookOf(p)!;
    s.strokes.save([for (var i = 0; i < 300; i++) _ink('a$i', p, i)]);
    // A drag's commit replacing every stroke, a slow step per turn.
    final steps = s.strokes.editSteps(
      [for (var i = 0; i < 300; i++) 'a$i'],
      [for (var i = 0; i < 300; i++) _ink('b$i', p, i)],
    );
    expect(steps.length, greaterThan(2));
    s.database.steps.add([
      for (final step in steps)
        () {
          final watch = Stopwatch()..start();
          while (watch.elapsedMicroseconds < 5000) {}
          step();
        },
    ]);
    expect(s.database.steps.isOpen, isTrue);
    final made = (await s.versions.save(notebook, name: 'mid'))!;
    expect(await versionInk(made, p), {for (var i = 0; i < 300; i++) 'b$i'});
  });

  test('a pack reused by a version being made is not collected before it is saved', () async {
    final p = page();
    final notebook = s.pages.notebookOf(p)!;
    s.strokes.save([for (var i = 0; i < 5; i++) _ink('a$i', p, i)]);
    final v1 = (await s.versions.save(notebook, name: 'one'))!;
    final packs = (await s.versions.content.body(v1)).packs;
    // Only v1 kept its packs and table; gone, they are due a week later.
    s.versions.delete([v1.id]);
    await s.blobGc.run();
    clock.now += const Duration(days: 8).inMilliseconds;
    // A version made of the same content reuses them; collection runs
    // while it is made (before it is saved).
    final made = (await s.versions.snapshots.build(notebook, kind: VersionKind.named))!;
    expect((await s.versions.content.body(made)).packs, packs);
    final deleted = await s.blobGc.run();
    s.versions.store.save(made);
    expect(deleted, isEmpty);
    for (final sha in [...packs, ...made.table]) {
      expect(await s.blobs.has(sha), isTrue, reason: sha);
    }
  });

  test('ink arriving while a restore saves the state before it is kept in that version, or '
      'live', () async {
    final first = page();
    final notebook = s.pages.notebookOf(first)!;
    for (var i = 1; i < 30; i++) {
      s.pages.addPage(notebook);
    }
    final pages = [for (final p in s.pages.pagesOf(notebook)) p.id];
    for (final (n, p) in pages.indexed) {
      s.strokes.save([for (var i = 0; i < 40; i++) _ink('$p-$i', p, n * 100 + i)]);
    }
    final v1 = (await s.versions.save(notebook, name: 'one'))!;
    s.strokes.save([_ink('x', first, 9000)]);
    // Sync writes to the notebook a turn at a time while it restores.
    final arrived = <(String, String)>[];
    final writer = Timer.periodic(Duration.zero, (t) {
      if (arrived.length == 12) return t.cancel();
      final p = pages[(arrived.length * 7) % pages.length];
      final id = 'pulled${arrived.length}';
      s.strokes.save([_ink(id, p, 9001 + arrived.length)]);
      arrived.add((id, p));
    });
    final restored = await s.versions.restore(v1);
    writer.cancel();
    expect(arrived, isNotEmpty);
    final before = restored.before!;
    expect(await versionInk(before, first), contains('x'));
    for (final (id, p) in arrived) {
      final live = s.database.db.select('SELECT 1 FROM strokes WHERE id = ? AND deleted = 0', [
        id,
      ]).isNotEmpty;
      expect(live || (await versionInk(before, p)).contains(id), isTrue, reason: '$id lost');
    }
  });

  test('when the notebook changes during every try, the last makes the version before the '
      'restore in its transaction: nothing synced in is lost', () async {
    final first = page();
    final notebook = s.pages.notebookOf(first)!;
    final second = s.pages.addPage(notebook).id;
    s.strokes.save([for (var i = 0; i < 5; i++) _ink('a$i', first, i)]);
    final v1 = (await s.versions.save(notebook, name: 'one'))!;
    s.strokes.save([_ink('x', second, 100)]);
    // Sync writes to the notebook after every try has made its version.
    final tries = <int>[];
    s.versions.restorer.debugBuilt = (attempt) {
      tries.add(attempt);
      s.strokes.save([_ink('pulled$attempt', attempt.isEven ? first : second, 200 + attempt)]);
    };
    final restored = await s.versions.restore(v1);
    expect(tries, [for (var i = 1; i <= VersionRestorer.attempts; i++) i]);
    final before = restored.before!;
    final ink = {...await versionInk(before, first), ...await versionInk(before, second)};
    expect(ink, containsAll(['x', for (final i in tries) 'pulled$i']));
    final live = {
      for (final row in s.database.db.select(
        'SELECT id FROM strokes WHERE deleted = 0 AND surface_id IN (?, ?)',
        [first, second],
      ))
        row['id'] as String,
    };
    expect(live, {for (var i = 0; i < 5; i++) 'a$i'}, reason: 'restored');
    // Its blobs were stored after the restore, its summary completed.
    for (final sha in [...(await s.versions.content.body(before)).packs, ...before.table]) {
      expect(await s.blobs.has(sha), isTrue, reason: sha);
    }
    expect(before.summary.strokesAdded, 1 + VersionRestorer.attempts);
    expect(s.versions.store.get(before.id)!.summary.strokesAdded, before.summary.strokesAdded);
    expect(before.size, greaterThan(0));
  });
}
