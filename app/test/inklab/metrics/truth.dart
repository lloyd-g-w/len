import 'dart:math' as math;
import 'dart:ui';

import 'package:len/ink/input/pen_stabiliser.dart';
import 'package:len/ink/lab/raw_samples.dart';

import 'polyline_index.dart';

/// What a stroke should look like, in surface-local logical px: the path
/// the pen tip travelled and its pressure along it.
///
/// For simulated cases this is exact ([exact]); for real recordings it is
/// the raw digitiser samples (jitter included), so it can only judge
/// fidelity to the input.
class Truth {
  Truth({
    required this.path,
    required this.pressure,
    this.cusps = const [],
    this.isTap = false,
    this.exact = true,
  });

  /// The raw samples of [contact] as truth.
  factory Truth.ofContact(RawContact contact) {
    final s = contact.samples;
    final duration = s.isEmpty ? 0 : s.last.timeUs - s.first.timeUs;
    var travel = 0.0;
    for (var i = 1; i < s.length; i++) {
      travel += (s[i].position - s[i - 1].position).distance;
    }
    return Truth(
      path: [for (final x in s) x.position],
      pressure: [for (final x in s) x.pressure],
      isTap: duration < 80000 && travel < 3,
      exact: false,
    );
  }

  final List<Offset> path;
  final List<double> pressure;

  /// Deliberate sharp reversals (tips of a "v").
  final List<Offset> cusps;
  final bool isTap;
  final bool exact;
}

/// [truth] as the pen's stabiliser at [streamline] draws it (screen px, as
/// truths are): its path through the same pulled string ([PenStabiliser]),
/// caught up at the end, each cusp moved to the nearest point of that
/// path. The string is deliberate smoothing (it cuts corners by its
/// length): the engine is judged on drawing what the stabiliser gives,
/// as at 0 on drawing the pen's path. At 0 (off), [truth] itself.
Truth stabilisedTruth(Truth truth, double streamline) {
  final params = StabiliserParams.of(streamline);
  if (params == null || truth.path.length < 2) return truth;
  final s = PenStabiliser(params)..begin(truth.path.first);
  final path = [truth.path.first];
  final pressure = [truth.pressure.first];
  for (var i = 1; i < truth.path.length; i++) {
    path.add(s.add(truth.path[i]));
    pressure.add(truth.pressure[math.min(i, truth.pressure.length - 1)]);
  }
  // The catch-up retraces the pen's last points: their pressures.
  final rest = s.catchUp();
  for (var k = 0; k < rest.length; k++) {
    path.add(rest[k]);
    final i = truth.pressure.length - rest.length + k;
    pressure.add(truth.pressure[i.clamp(0, truth.pressure.length - 1)]);
  }
  final index = PolylineIndex(path, cell: 3);
  return Truth(
    path: path,
    pressure: pressure,
    cusps: [for (final c in truth.cusps) _nearestOn(path, index.nearest(c).segment, c)],
    isTap: truth.isTap,
    exact: truth.exact,
  );
}

/// The point of [path]'s segment [i] nearest [p].
Offset _nearestOn(List<Offset> path, int i, Offset p) {
  final a = path[i], b = path[math.min(i + 1, path.length - 1)];
  final d = b - a;
  final l2 = d.dx * d.dx + d.dy * d.dy;
  if (l2 == 0) return a;
  final t = (((p - a).dx * d.dx + (p - a).dy * d.dy) / l2).clamp(0.0, 1.0);
  return a + d * t;
}
