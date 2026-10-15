import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/lab/input_recording.dart';
import 'package:len/ink/lab/raw_samples.dart';
import 'package:len/ink/lab/replay.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/viewport.dart';

import 'inklab/sim/cases.dart';
import 'inklab/sim/digitiser.dart';
import 'inklab/sim/pen_motion.dart';
import 'support/real_ink.dart';
import 'support/real_scribbles.dart';

/// Hold to snap and scribble to erase against the Ink Lab's real S Pen
/// recordings (docs/INK_LAB.md, "Gestures on real ink"). Contacts are
/// numbered as [rawContacts] lists them.

/// The shapes the recordings hold: what they must snap to when held.
const shapes = {
  'real_spen_01': {40: ShapeKind.ellipse, 48: ShapeKind.ellipse}, // rings around words
  'real_spen_02': {7: ShapeKind.line},
};

/// Straight strokes of letters (stems, bars, an underline): held, they
/// may become a line (and nothing else). Every other stroke is writing or
/// a curve and must never snap.
const straight = {
  'real_spen_01': {5, 6, 8, 34, 35, 37, 38, 39, 43, 44, 46, 47, 49, 55, 56, 58, 59, 60, 62, 64, 66},
};

/// Replays [recording] through the real pipeline on the recording's own
/// clock (so the hold timer fires only where the pen really rested),
/// with hold to snap and scribble to erase on or off; returns the
/// strokes it committed and how many are kept.
({List<Stroke> committed, int kept}) replay(InputRecording recording, {required bool gestures}) {
  final db = AppDatabase.inMemory();
  final model = SurfaceModel(
    surfaceId: 's',
    repository: StrokeRepository(db, deviceId: 'd'),
  );
  final committed = <Stroke>[];
  fakeAsync((async) {
    var now = recording.entries.first.t;
    final driver = ReplayDriver(
      recording,
      model: model,
      live: LiveInk(),
      viewport: ViewportController(),
      holdToSnap: gestures,
      advance: (t) {
        if (t <= now) return;
        async.elapse(Duration(microseconds: t - now));
        now = t;
      },
    );
    driver.tools.scribbleToErase = gestures;
    for (var step = driver.step(); step != null; step = driver.step()) {
      committed.addAll(step.committed);
    }
    async.flushMicrotasks();
  });
  final kept = model.loadedStrokeCount;
  model.dispose();
  db.close();
  return (committed: committed, kept: kept);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a replay runs hold to snap on the recording\'s clock', () {
    // A line drawn in 0.25 s, then the pen resting for 0.8 s.
    final motion = PenMotion(
      duration: 1.05,
      at: (t) =>
          Offset.lerp(const Offset(100, 300), const Offset(400, 320), (t / 0.25).clamp(0, 1))!,
      pressure: (_) => 0.5,
    );
    final recording = Digitiser(const DigitiserModel())
        .record([SimContact(motion, start: 0)], pen: defaultPen)
        .recording;
    expect(replay(recording, gestures: false).committed.single.shape, isNull);
    expect(replay(recording, gestures: true).committed.single.shape?.kind, ShapeKind.line);
  });

  for (final name in realRecordings) {
    final recording = loadRecording(name);
    final contacts = penContacts(recording);

    test('$name as written: no snaps, nothing scribbled away', () {
      final plain = replay(recording, gestures: false);
      final live = replay(recording, gestures: true);
      expect(live.committed, hasLength(plain.committed.length));
      expect(live.kept, plain.kept, reason: 'a scribble erased ink');
      expect([for (final s in live.committed) s.shape], everyElement(isNull));
      expect(
        [for (final s in live.committed) s.points.length],
        [for (final s in plain.committed) s.points.length],
      );
    });

    test('$name: no stroke rests 600 ms as written (the longest rest is far shorter)', () {
      for (final (k, c) in contacts) {
        expect(longestRestMs(c), lessThan(300), reason: 'contact $k');
      }
    });

    for (final scale in [1.0, 0.5]) {
      test('$name at $scale×, every stroke held at its end: only shapes snap', () {
        final rig = PenRig();
        addTearDown(rig.dispose);
        for (final (k, c) in contacts) {
          final drawn = rig.draw(withHold(rescaled(fromZero(c), scale: scale), 700));
          expect(drawn.erased, 0, reason: 'contact $k erased ink');
          final kind = drawn.stroke?.shape?.kind;
          final shape = shapes[name]?[k];
          if (shape != null) {
            expect(kind, shape, reason: 'contact $k');
          } else if (straight[name]?.contains(k) ?? false) {
            expect(kind, anyOf(isNull, ShapeKind.line), reason: 'contact $k');
          } else {
            expect(kind, isNull, reason: 'contact $k');
          }
        }
      });
    }

    test('$name: no stroke is a scribble, at 0.25–3× and up to 3× as fast', () {
      for (final (k, c) in contacts) {
        for (final scale in [0.25, 0.33, 0.5, 0.75, 1.0, 2.0, 3.0]) {
          for (final pace in [1.0, 0.5, 0.33]) {
            expect(
              scribbles(rescaled(c.samples, scale: scale, pace: pace)),
              isFalse,
              reason: 'contact $k at $scale×, pace $pace',
            );
          }
        }
      }
    });
  }
}

/// The longest the pen stayed within the hold tolerance (4 px) of where
/// it then was during [contact] (ms), as hold to snap times a rest.
int longestRestMs(RawContact contact) {
  final s = contact.samples;
  var longest = 0;
  for (var i = 1; i < s.length; i++) {
    var from = i;
    while (from > 0 && (s[from - 1].position - s[i].position).distance <= 4) {
      from--;
    }
    final rest = (s[i].timeUs - s[from].timeUs) ~/ 1000;
    if (rest > longest) longest = rest;
  }
  return longest;
}
