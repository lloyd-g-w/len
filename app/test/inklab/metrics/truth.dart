import 'dart:ui';

import 'package:len/ink/lab/raw_samples.dart';

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
