import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/lab/raw_samples.dart';

import 'support/ideal_shapes.dart';
import 'support/real_ink.dart';
import 'support/real_profile.dart';
import 'support/real_scribbles.dart';

/// Shapes and scribbles drawn the way the real S Pen strokes of the Ink
/// Lab's recordings were: their timing, speed changes, pressure and
/// jitter applied to ideal and hand-drawn shapes, held and lifted through
/// the real pipeline; and the recordings' real zigzags squeezed into
/// scribbles (docs/INK_LAB.md, "Gestures on real ink").
///
/// `--dart-define=INKLAB_TABLE=true` prints the rates over every profile
/// and both jitter measures (the numbers in the doc), ≈ 1 min.
const bool table = bool.fromEnvironment('INKLAB_TABLE');

/// Every real pen stroke of 250 ms or more, as a profile.
List<(String, RealProfile)> donors({double smoothingMs = 8}) => [
  for (final name in realRecordings)
    for (final (k, c) in penContacts(loadRecording(name)))
      if (c.samples.last.timeUs - c.samples.first.timeUs >= 250000)
        ('$name#$k', RealProfile.of(c, smoothingMs: smoothingMs)),
];

/// Outcomes per shape ("ideal rectangle", …): snapped to the right kind,
/// to none, to another kind.
typedef Tally = Map<String, ({int ok, int none, int wrong})>;

/// Draws every shape with each of [profiles], at [sizes] and turned by
/// [angles], held 700 ms at its end; [misses] collects what went wrong.
Tally snapRates(
  List<(String, RealProfile)> profiles, {
  List<double> sizes = const [60, 120, 240],
  List<double> angles = const [0, 0.35],
  List<String>? misses,
}) {
  final tally = <String, ({int ok, int none, int wrong})>{};
  for (final hand in [false, true]) {
    for (final size in sizes) {
      for (final angle in angles) {
        final rig = PenRig();
        for (final (i, (donor, profile)) in profiles.indexed) {
          const centre = Offset(400, 400);
          final cases = hand
              ? handShapes(centre, size, angle: angle, seed: i)
              : idealShapes(centre, size, angle: angle);
          for (final c in cases) {
            final kind = rig.draw(withHold(profile.apply(c.path), 700)).stroke?.shape?.kind;
            final key = '${hand ? 'hand' : 'ideal'} ${c.name}';
            final t = tally[key] ?? (ok: 0, none: 0, wrong: 0);
            tally[key] = (
              ok: t.ok + (kind == c.kind ? 1 : 0),
              none: t.none + (kind == null ? 1 : 0),
              wrong: t.wrong + (kind != null && kind != c.kind ? 1 : 0),
            );
            if (kind != c.kind) misses?.add('$key $size px at $angle, $donor → ${kind?.name}');
          }
        }
        rig.dispose();
      }
    }
  }
  return tally;
}

String _row(String key, ({int ok, int none, int wrong}) t) {
  final n = t.ok + t.none + t.wrong;
  return '| $key | ${(100 * t.ok / n).toStringAsFixed(1)} % | ${t.none} | ${t.wrong} | $n |';
}

/// The zigzags of real_spen_02: passes back and forth 100–400 px long,
/// moving on by about their length every pass.
const zigzags = [10, 11, 14, 15, 17, 18, 19, 21, 22, 23];

/// How many of the [zigzags] squeezed into scribbles are recognised.
int scribbleHits({required double amplitude, required double spread, required double passMs}) {
  final contacts = {for (final (k, c) in penContacts(loadRecording('real_spen_02'))) k: c};
  var hits = 0;
  for (final z in zigzags) {
    final s = squeezed(contacts[z]!.samples, amplitude: amplitude, spread: spread, passMs: passMs);
    if (scribbles(s)) hits++;
  }
  return hits;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shapes drawn with real strokes\' timing, pressure and jitter snap', () {
    final all = donors();
    final misses = <String>[];
    final tally = snapRates([for (var i = 0; i < all.length; i += 3) all[i]], misses: misses);
    for (final MapEntry(:key, value: t) in tally.entries) {
      final n = t.ok + t.none + t.wrong;
      expect(t.ok / n, greaterThanOrEqualTo(0.95), reason: '$key: ${misses.join('\n')}');
      expect(t.wrong / n, lessThanOrEqualTo(0.01), reason: '$key: ${misses.join('\n')}');
    }
  });

  test('real zigzags squeezed into scribbles are recognised', () {
    for (final amplitude in [40.0, 80.0, 160.0]) {
      for (final spread in [0.1, 0.2, 0.3]) {
        for (final passMs in [60.0, 100.0, 150.0]) {
          expect(
            scribbleHits(amplitude: amplitude, spread: spread, passMs: passMs),
            zigzags.length,
            reason: '$amplitude px, spread $spread, $passMs ms a pass',
          );
        }
      }
    }
    // As written they are no scribbles: they move on too far each pass.
    final contacts = {for (final (k, c) in penContacts(loadRecording('real_spen_02'))) k: c};
    for (final z in zigzags) {
      expect(scribbles(contacts[z]!.samples), isFalse, reason: 'contact $z');
    }
  });

  test('a squeezed real zigzag over a real word erases it', () {
    final rig = PenRig();
    addTearDown(rig.dispose);
    final word = penContacts(loadRecording('real_spen_01')).firstWhere((c) => c.$1 == 41).$2;
    // The word (an "x", 57 × 41 px) at a third of its size inside the band.
    final small = rescaled(fromZero(word), scale: 1 / 3);
    final at = const Offset(520, 504) - small.first.position;
    final placed = [for (final s in small) RawSample(s.position + at, s.pressure, s.timeUs)];
    expect(rig.draw(placed).stroke, isNotNull);
    final zigzag = penContacts(loadRecording('real_spen_02')).firstWhere((c) => c.$1 == 19).$2;
    final scribble = squeezed(zigzag.samples, amplitude: 80, spread: 0.3, passMs: 90);
    final drawn = rig.draw(scribble);
    expect(drawn.erased, 1);
    expect(drawn.stroke, isNull);
  });

  test('rates over every profile (INKLAB_TABLE)', () {
    for (final smoothing in [8.0, 25.0]) {
      final misses = <String>[];
      final tally = snapRates(donors(smoothingMs: smoothing), misses: misses);
      // ignore: avoid_print
      print(
        '\nJitter beyond a ${smoothing.round()} ms fit\n'
        '| Shape | snapped right | none | other kind | strokes |\n|---|---|---|---|---|\n'
        '${[for (final e in tally.entries) _row(e.key, e.value)].join('\n')}\n'
        '${misses.join('\n')}',
      );
    }
    final rows = StringBuffer(
      '\n| Spread | amplitude | 60 ms | 100 ms | 150 ms | 200 ms | 250 ms |\n',
    );
    rows.writeln('|---|---|---|---|---|---|---|');
    for (final spread in [0.1, 0.2, 0.3, 0.4, 0.5]) {
      for (final amplitude in [20.0, 40.0, 80.0, 160.0]) {
        rows.write('| $spread | $amplitude px |');
        for (final passMs in [60.0, 100.0, 150.0, 200.0, 250.0]) {
          final hits = scribbleHits(amplitude: amplitude, spread: spread, passMs: passMs);
          rows.write(' $hits/${zigzags.length} |');
        }
        rows.writeln();
      }
    }
    // ignore: avoid_print
    print(rows);
  }, skip: !table);
}
