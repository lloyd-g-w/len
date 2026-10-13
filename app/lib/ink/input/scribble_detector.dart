import 'dart:math' as math;
import 'dart:ui';

/// "Scribble to erase": recognises a fast back-and-forth scribble in a
/// pen stroke (screen pixels and milliseconds, fed as the pen moves).
///
/// Deliberately strict, so writing never trips it (checked against the Ink
/// Lab's real S Pen recordings and simulated cursive). A scribble needs
/// [minPasses] consecutive passes (so `minPasses - 1` sharp reversals),
/// all within [maxDuration], where every pass
///  * nearly reverses the one before it (within ~35°),
///  * is at least [minAmplitude] long and not much shorter than the others,
///  * is fairly straight,
/// and the passes stay in a band: their spread across the scribble's axis
/// is at most [maxSpread] of its amplitude. Cursive (m, n, u, w) reverses
/// as sharply but moves on along the line, so its spread is large.
class ScribbleDetector {
  /// Spacing (pixels) of the resampled path the reversals are found on.
  static const double spacing = 3;

  /// Passes (each a reversal of the one before) a scribble needs.
  static const int minPasses = 6;

  /// The time those passes may take.
  static const int maxDuration = 1200;

  /// The shortest pass (pixels): smaller wiggles are jitter or letters.
  static const double minAmplitude = 14;

  /// How far the passes may spread across their axis, relative to their
  /// amplitude.
  static const double maxSpread = 0.5;

  /// How close (screen pixels) the scribble must pass to ink to erase it,
  /// at least.
  static const double reach = 4;

  /// The cosine of the sharpest turn that is no reversal (about 135°).
  static const double _reversal = -0.7;

  final List<Offset> _points = [];
  final List<int> _times = [];

  /// Starts a new stroke at [at].
  void begin(Offset at, int timeMs) {
    _points
      ..clear()
      ..add(at);
    _times
      ..clear()
      ..add(timeMs);
  }

  /// The pen moved to [at].
  void add(Offset at, int timeMs) {
    if (_points.isEmpty) return begin(at, timeMs);
    if ((at - _points.last).distance < spacing) return;
    _points.add(at);
    _times.add(timeMs);
  }

  /// Whether the stroke so far holds a scribble.
  bool get isScribble => detect(_points, _times);

  /// Whether the path [points] (resampled at about [spacing], with the
  /// time of each in [times]) holds a scribble.
  static bool detect(List<Offset> points, List<int> times) {
    final passes = _passes(points);
    if (passes.length < minPasses) return false;
    for (var i = 0; i + minPasses <= passes.length; i++) {
      if (_isScribble(points, times, passes.sublist(i, i + minPasses))) return true;
    }
    return false;
  }

  /// The path split at its sharp reversals: (first, last) point indices.
  static List<(int, int)> _passes(List<Offset> p) {
    const w = 3; // Directions over ±9 px: jitter doesn't count, round turns do.
    final turns = <int>[];
    var i = w;
    while (i < p.length - w) {
      if (_cosTurn(p, i, w) > _reversal) {
        i++;
        continue;
      }
      // One reversal: the sharpest point of the run of turning points.
      var best = i, bestCos = _cosTurn(p, i, w);
      var j = i + 1;
      while (j < p.length - w && _cosTurn(p, j, w) <= _reversal) {
        final c = _cosTurn(p, j, w);
        if (c < bestCos) (best, bestCos) = (j, c);
        j++;
      }
      turns.add(best);
      i = j;
    }
    final ends = [0, ...turns, p.length - 1];
    return [for (var k = 0; k + 1 < ends.length; k++) (ends[k], ends[k + 1])];
  }

  /// The cosine of the turn at point [i] (direction in vs out over [w]).
  static double _cosTurn(List<Offset> p, int i, int w) {
    final a = p[i] - p[i - w], b = p[i + w] - p[i];
    final d = a.distance * b.distance;
    return d == 0 ? 1 : (a.dx * b.dx + a.dy * b.dy) / d;
  }

  static bool _isScribble(List<Offset> p, List<int> t, List<(int, int)> passes) {
    final first = passes.first.$1, last = passes.last.$2;
    if (t[last] - t[first] > maxDuration) return false;
    final chords = [for (final (a, b) in passes) p[b] - p[a]];
    // Consecutive passes nearly reverse each other.
    for (var k = 1; k < chords.length; k++) {
      final a = chords[k - 1], b = chords[k];
      final d = a.distance * b.distance;
      if (d == 0 || (a.dx * b.dx + a.dy * b.dy) / d > -0.8) return false;
    }
    // The axis: the passes, all turned one way.
    var axis = Offset.zero;
    for (final (k, c) in chords.indexed) {
      axis += k.isEven ? c : -c;
    }
    if (axis.distance == 0) return false;
    final u = axis / axis.distance, n = Offset(-u.dy, u.dx);
    final lengths = [for (final c in chords) (c.dx * u.dx + c.dy * u.dy).abs()]..sort();
    final amplitude = lengths[lengths.length ~/ 2];
    if (amplitude < minAmplitude || lengths.first < 0.5 * amplitude) return false;
    // Each pass fairly straight (not an arch or a loop).
    for (final (k, (a, b)) in passes.indexed) {
      var length = 0.0;
      for (var i = a + 1; i <= b; i++) {
        length += (p[i] - p[i - 1]).distance;
      }
      if (length > 1.6 * chords[k].distance) return false;
    }
    // The passes stay in a band across the axis.
    var lo = double.infinity, hi = double.negativeInfinity;
    for (var i = first; i <= last; i++) {
      final across = p[i].dx * n.dx + p[i].dy * n.dy;
      lo = math.min(lo, across);
      hi = math.max(hi, across);
    }
    return hi - lo <= maxSpread * amplitude;
  }
}
