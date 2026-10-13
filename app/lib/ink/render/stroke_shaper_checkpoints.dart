part of 'stroke_shaper.dart';

/// The final state of a [StrokeShaper] after an [StrokeShaper.update]
/// ([StrokeShaper.checkpoint], [StrokeShaper.rollBack]).
class _Checkpoint {
  /// The current final state of [s].
  _Checkpoint.of(StrokeShaper s, this.id)
    : seg = s._seg,
      next = s._next,
      resFinal = s._resFinal,
      radDone = s._radDone,
      corners = s._corners.length,
      scan = s._scan,
      runFirst = s._runFirst,
      runBest = s._runBest,
      runScore = s._runScore,
      posFinal = s._posFinal,
      roDone = s._roDone;

  final int id;
  final int seg;
  final double next;
  final int resFinal, radDone, corners, scan, runFirst, runBest;
  final double runScore;
  final int posFinal, roDone;

  /// Restores this state into [s] and drops its input samples from
  /// [sample] on.
  void restore(StrokeShaper s, int sample) {
    s._seg = seg;
    s._next = next;
    s._resFinal = resFinal;
    s._radDone = radDone;
    s._corners.removeRange(corners, s._corners.length);
    s._scan = scan;
    s._runFirst = runFirst;
    s._runBest = runBest;
    s._runScore = runScore;
    s._posFinal = posFinal;
    s._roDone = roDone;
    s._sx.length = sample;
    s._sy.length = sample;
    s._sr.length = sample;
    s.pointCount = s._samplePoint[sample];
    s._samplePoint.removeRange(sample, s._samplePoint.length);
  }
}
