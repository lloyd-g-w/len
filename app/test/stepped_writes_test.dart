import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';

/// [SteppedWrites]: steps across turns in one transaction.
void main() {
  int count(AppDatabase d) =>
      d.db.select("SELECT COUNT(*) AS n FROM settings WHERE key LIKE 'k%'").first['n'] as int;

  // A step that takes longer than the budget, so each turn runs one.
  void Function() slowStep(AppDatabase d, int i) => () {
    final watch = Stopwatch()..start();
    while (watch.elapsedMicroseconds < 5000) {}
    d.execute('INSERT INTO settings VALUES (?, ?)', ['k$i', '$i']);
  };

  test('runs a turn now and the rest in later turns, committing after the last', () {
    fakeAsync((async) {
      final d = AppDatabase.inMemory();
      d.steps.add([for (var i = 0; i < 3; i++) slowStep(d, i)]);
      expect(d.steps.isOpen, isTrue);
      expect(d.db.autocommit, isFalse);
      async.flushTimers();
      expect(d.steps.isOpen, isFalse);
      expect(d.steps.turns, hasLength(3));
      expect(count(d), 3);
      expect(d.db.autocommit, isTrue);
      d.close();
    });
  });

  test('a transaction of its own finishes the steps first', () {
    fakeAsync((async) {
      final d = AppDatabase.inMemory();
      d.steps.add([for (var i = 0; i < 3; i++) slowStep(d, i)]);
      expect(
        () => d.transaction(() {
          expect(d.steps.isOpen, isFalse);
          expect(count(d), 3);
          throw StateError('rolled back alone');
        }),
        throwsStateError,
      );
      expect(count(d), 3);
      async.flushTimers();
      d.close();
    });
  });

  test('a push reads no half edit: dirty rows finish the steps first', () {
    fakeAsync((async) {
      final d = AppDatabase.inMemory();
      final strokes = StrokeRepository(d, deviceId: 'd');
      Stroke stroke(int i) => Stroke(
        id: 's$i',
        surfaceId: 'p',
        tool: InkTool.ballpoint,
        color: 0xFF000000,
        width: 2,
        points: const [StrokePoint(0, 0, 0.5), StrokePoint(10, 10, 0.5)],
        createdAt: i,
      );
      final steps = strokes.editSteps(const [], [for (var i = 0; i < 200; i++) stroke(i)]);
      expect(steps.length, greaterThan(1));
      d.steps.add([
        for (final step in steps)
          () {
            final watch = Stopwatch()..start();
            while (watch.elapsedMicroseconds < 5000) {}
            step();
          },
      ]);
      expect(d.steps.isOpen, isTrue, reason: 'more steps than a turn');
      expect(strokes.dirtyRecords(1000), hasLength(200));
      expect(d.steps.isOpen, isFalse);
      async.flushTimers();
      d.close();
    });
  });

  test('a failing step rolls back the whole transaction', () {
    fakeAsync((async) {
      final d = AppDatabase.inMemory();
      d.steps.add([slowStep(d, 0), () => throw StateError('step failed')]);
      expect(d.steps.finish, throwsStateError);
      expect(d.steps.isOpen, isFalse);
      expect(count(d), 0);
      expect(d.db.autocommit, isTrue);
      d.close();
    });
  });
}
