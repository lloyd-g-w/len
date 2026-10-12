import 'dart:typed_data';

/// A stroke's smoothed centre line: samples a uniform arc-length [step]
/// apart, each with its outline radius, and the [corners] (sharp
/// reversals) that split it into stretches. Produced by `StrokeShaper`;
/// used for measurements (Ink Lab, tests).
class Centerline {
  Centerline(this.x, this.y, this.r, this.step, {this.corners = const [], int? live})
    : live = live ?? x.length;

  final Float64List x, y, r;

  /// Distance between consecutive samples (the last one may be closer).
  final double step;

  /// Sample indices of sharp reversals; smoothing never crosses them.
  final List<int> corners;

  int get length => x.length;

  /// How many samples live ink shows (fewer than [length] with the
  /// stabiliser on, `StrokeShaper.liveLength`).
  final int live;
}
