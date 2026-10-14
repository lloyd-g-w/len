import 'dart:ui';

import '../render/flat_ends.dart';

/// A sample as the overlay keeps it.
class WetSample {
  const WetSample(this.position, this.pressure, this.timeMs);
  final Offset position;
  final double pressure;
  final int timeMs;
}

/// One piece the overlay draws: the hull of two circles.
class WetSegment {
  const WetSegment(
    this.a,
    this.b,
    this.ra,
    this.rb, {
    this.flatA = false,
    this.flatB = false,
    this.cuts = const [],
    this.sweeps = const [],
  });
  final Offset a, b;
  final double ra, rb;

  /// A butt cap at [a] / [b] (the stroke's start, the drawn end); a dot
  /// (a == b) with both is a square.
  final bool flatA, flatB;

  /// The lines of the flat ends' butt caps this piece is cut off at
  /// (`WetInkEnds`): what lies beyond one, on the side its normal faces,
  /// is not drawn.
  final List<EndLine> cuts;

  /// Within a flat end's zone, the piece is the area a flat nib sweeps
  /// between these cross-sections (`emitSweep`), not the hull of its
  /// circles; then cut off at [cuts].
  final List<(CrossSection, CrossSection)> sweeps;
}
