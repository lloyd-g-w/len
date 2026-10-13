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
///  * is at least [minAmplitude] long and not much shorter than the others
///    (nor, but for the first and last, much longer),
///  * is fairly straight,
/// and the passes stay in a band: their spread across the scribble's axis
/// is at most [maxSpread] of its amplitude. Cursive (m, n, u, w) reverses
/// as sharply but moves on along the line, so its spread is large.
///
/// Only the part that zigzags counts ([windows]): what the stroke crossed
/// before or after doesn't erase.
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

  /// The zigzags found so far: (first, last) indices into [_points],
  /// in order, not overlapping.
  final List<(int, int)> _windows = [];

  /// How many points the last look covered.
  int _looked = 0;

  /// Starts a new stroke at [at].
  void begin(Offset at, int timeMs) {
    _points
      ..clear()
      ..add(at);
    _times
      ..clear()
      ..add(timeMs);
    _windows.clear();
    _looked = 0;
  }

  /// The pen moved to [at].
  void add(Offset at, int timeMs) {
    if (_points.isEmpty) return begin(at, timeMs);
    if ((at - _points.last).distance < spacing) return;
    _points.add(at);
    _times.add(timeMs);
    // Look now and then: a zigzag is found while it is in the last
    // [maxDuration], however long the stroke goes on after it.
    if (_points.length - _looked >= _lookEvery) _look();
  }

  /// How many points may come between two looks.
  static const int _lookEvery = 4;

  /// Whether the stroke so far holds a scribble.
  bool get isScribble => windows.isNotEmpty;

  /// The parts of the stroke that zigzag, as screen paths: only these
  /// erase (a lead-in or a pass that runs on beyond the others doesn't).
  List<List<Offset>> get paths => [for (final (a, b) in windows) _points.sublist(a, b + 1)];

  /// The zigzags of the stroke so far, (first, last) indices into its
  /// resampled points. Each look scans only the stroke's last
  /// [maxDuration] (no scribble is longer), so it costs the same however
  /// long the stroke is.
  List<(int, int)> get windows {
    if (_looked != _points.length) _look();
    return _windows;
  }

  void _look() {
    _looked = _points.length;
    var from = _times.length - 1;
    final since = _times.last - maxDuration;
    while (from > 0 && _times[from - 1] >= since) {
      from--;
    }
    // Room to find the turn at the first pass's start.
    from = math.max(0, from - 2 * _turnReach);
    for (final w in find(_points, _times, from: from)) {
      _merge(w);
    }
  }

  /// Adds [w] to [_windows], joining those it overlaps or touches.
  void _merge((int, int) w) {
    var (a, b) = w;
    final kept = <(int, int)>[];
    for (final (c, d) in _windows) {
      if (c <= b + 1 && a <= d + 1) {
        a = math.min(a, c);
        b = math.max(b, d);
      } else {
        kept.add((c, d));
      }
    }
    _windows
      ..clear()
      ..addAll(kept)
      ..add((a, b))
      ..sort((x, y) => x.$1.compareTo(y.$1));
  }

  /// Whether the path [points] (resampled at about [spacing], with the
  /// time of each in [times]) holds a scribble.
  static bool detect(List<Offset> points, List<int> times) => find(points, times).isNotEmpty;

  /// The scribbles in [points] from index [from] on: each run of
  /// [minPasses] passes that makes one, as (first, last) point indices,
  /// with its outer passes cut to the span of the inner ones. When [from]
  /// is past the start, the part-pass it begins with is no pass.
  static List<(int, int)> find(List<Offset> points, List<int> times, {int from = 0}) {
    final passes = _passes(points, from);
    if (from > 0 && passes.isNotEmpty) passes.removeAt(0);
    final found = <(int, int)>[];
    for (var i = 0; i + minPasses <= passes.length; i++) {
      final window = _scribble(points, times, passes.sublist(i, i + minPasses));
      if (window != null) found.add(window);
    }
    return found;
  }

  /// How many points either side a turn is measured over.
  static const int _turnReach = 3;

  /// The path split at its sharp reversals: (first, last) point indices.
  static List<(int, int)> _passes(List<Offset> p, int from) {
    const w = _turnReach; // Directions over ±9 px: jitter doesn't count, round turns do.
    final turns = <int>[];
    var i = from + w;
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
    final ends = [from, ...turns, p.length - 1];
    return [for (var k = 0; k + 1 < ends.length; k++) (ends[k], ends[k + 1])];
  }

  /// The cosine of the turn at point [i] (direction in vs out over [w]).
  static double _cosTurn(List<Offset> p, int i, int w) {
    final a = p[i] - p[i - w], b = p[i + w] - p[i];
    final d = a.distance * b.distance;
    return d == 0 ? 1 : (a.dx * b.dx + a.dy * b.dy) / d;
  }

  /// The window of [passes], if they make a scribble.
  static (int, int)? _scribble(List<Offset> p, List<int> t, List<(int, int)> passes) {
    final first = passes.first.$1, last = passes.last.$2;
    if (t[last] - t[first] > maxDuration) return null;
    final chords = [for (final (a, b) in passes) p[b] - p[a]];
    // Consecutive passes nearly reverse each other.
    for (var k = 1; k < chords.length; k++) {
      final a = chords[k - 1], b = chords[k];
      final d = a.distance * b.distance;
      if (d == 0 || (a.dx * b.dx + a.dy * b.dy) / d > -0.8) return null;
    }
    // The axis: the passes, all turned one way.
    var axis = Offset.zero;
    for (final (k, c) in chords.indexed) {
      axis += k.isEven ? c : -c;
    }
    if (axis.distance == 0) return null;
    final u = axis / axis.distance, n = Offset(-u.dy, u.dx);
    final lengths = [for (final c in chords) (c.dx * u.dx + c.dy * u.dy).abs()]..sort();
    final amplitude = lengths[lengths.length ~/ 2];
    if (amplitude < minAmplitude || lengths.first < 0.5 * amplitude) return null;
    // Inner passes not much longer either (the outer ones may run on: they
    // are cut below), so two scribbles joined by a stroke are two.
    for (final c in chords.sublist(1, chords.length - 1)) {
      if ((c.dx * u.dx + c.dy * u.dy).abs() > 2 * amplitude) return null;
    }
    // Each pass fairly straight (not an arch or a loop).
    for (final (k, (a, b)) in passes.indexed) {
      var length = 0.0;
      for (var i = a + 1; i <= b; i++) {
        length += (p[i] - p[i - 1]).distance;
      }
      if (length > 1.6 * chords[k].distance) return null;
    }
    // The passes stay in a band across the axis.
    var lo = double.infinity, hi = double.negativeInfinity;
    for (var i = first; i <= last; i++) {
      final across = p[i].dx * n.dx + p[i].dy * n.dy;
      lo = math.min(lo, across);
      hi = math.max(hi, across);
    }
    if (hi - lo > maxSpread * amplitude) return null;
    // The outer passes may run on (a lead-in, say): keep their part within
    // the span the inner passes sweep along the axis.
    var min = double.infinity, max = double.negativeInfinity;
    for (var i = passes[1].$1; i <= passes[passes.length - 2].$2; i++) {
      final along = p[i].dx * u.dx + p[i].dy * u.dy;
      min = math.min(min, along);
      max = math.max(max, along);
    }
    bool within(int i) {
      final along = p[i].dx * u.dx + p[i].dy * u.dy;
      return along >= min - spacing && along <= max + spacing;
    }

    var a = first, b = last;
    while (a < passes.first.$2 && !within(a)) {
      a++;
    }
    while (b > passes.last.$1 && !within(b)) {
      b--;
    }
    return (a, b);
  }
}
