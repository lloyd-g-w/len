import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
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
}
