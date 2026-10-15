part of 'stroke_shaper.dart';

/// Where [StrokeShaper]'s input points and samples fall: which sample a
/// point went into, and where each segment's resampled points begin (so a
/// piece of the line is resampled where the whole line's samples fall).
mixin _SampleIndex {
  int get pointCount;
  int get startSample;

  /// The first input point of each sample (merged points follow it).
  final List<int> _samplePoint = [];

  // Per segment: the arc length of its first resampled point from its
  // start ([phaseAt]) and that point's index ([firstSampleOf]); entries
  // before the start are unused.
  final DoubleBuffer _segNext = DoubleBuffer(), _segFirst = DoubleBuffer();

  /// The input sample point [point] went into.
  int sampleOfPoint(int point) {
    var lo = 0, hi = _samplePoint.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_samplePoint[mid] <= point) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The arc length from input sample [sample] to the first resampled
  /// point after it (0 < phase ≤ step), as of the last [StrokeShaper.update]; null
  /// where the line has no samples (before its start, after its end).
  /// A piece cut out of the line (the pixel eraser) is resampled with
  /// this phase, so its points fall where the line's did.
  double? phaseAt(int sample) {
    if (sample < startSample || sample >= _segNext.length) return null;
    return _segNext[sample];
  }

  /// The index of the first resampled point after input sample [sample],
  /// as of the last [StrokeShaper.update]; null as for [phaseAt].
  int? firstSampleOf(int sample) {
    if (sample < startSample || sample >= _segFirst.length) return null;
    return _segFirst[sample].toInt();
  }

  /// The input sample that input point [point] starts, or null when it was
  /// merged into the one before (closer than [ShapeParams.dedupe]).
  int? sampleStartingAt(int point) {
    if (point >= pointCount) return null;
    final s = sampleOfPoint(point);
    return _samplePoint[s] == point ? s : null;
  }
}
