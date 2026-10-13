part of 'stroke_shaper.dart';

/// 4. Corners and 5. positions: the low-pass filtered line, per stretch
/// between corners.
extension _Smoothing on StrokeShaper {
  /// Turn (radians) at sample [i] over the corner baseline.
  double _turnAt(int i) {
    final k = p.cornerK;
    final ax = _rx[i] - _rx[i - k], ay = _ry[i] - _ry[i - k];
    final bx = _rx[i + k] - _rx[i], by = _ry[i + k] - _ry[i];
    return math.atan2(ax * by - ay * bx, ax * bx + ay * by).abs();
  }

  /// How far sample [i] lies along the direction the line came in from
  /// before the run of sharp turns starting at [first]: the tip of a cusp
  /// is where the pen stops going that way (every corner turns > 90°). The
  /// sharpest turn over the baseline can be a sample or two past the tip.
  double _tipScore(int first, int i) {
    final k = p.cornerK;
    final ux = _rx[first] - _rx[first - k], uy = _ry[first] - _ry[first - k];
    return (_rx[i] - _rx[first]) * ux + (_ry[i] - _ry[first]) * uy;
  }

  void _findCorners(int count) {
    final k = p.cornerK;
    if (_scan < k) _scan = k;
    // Final part: samples whose baseline reaches only final samples.
    while (_scan + k < _resFinal) {
      if (_turnAt(_scan) > ShapeParams.minTurn) {
        if (_runFirst < 0) {
          _runFirst = _runBest = _scan;
          _runScore = 0;
        } else if (_tipScore(_runFirst, _scan) > _runScore) {
          _runBest = _scan;
          _runScore = _tipScore(_runFirst, _scan);
        }
      } else if (_runFirst >= 0) {
        _corners.add(_runBest);
        _runFirst = _runBest = -1;
        _runScore = 0;
      }
      _scan++;
    }
    // Provisional part, from a copy of the scan state.
    final found = List<int>.of(_corners);
    var first = _runFirst, best = _runBest;
    var score = _runScore;
    for (var i = _scan; i + k < count; i++) {
      if (_turnAt(i) > ShapeParams.minTurn) {
        if (first < 0) {
          first = best = i;
          score = 0;
        } else if (_tipScore(first, i) > score) {
          best = i;
          score = _tipScore(first, i);
        }
      } else if (first >= 0) {
        found.add(best);
        first = best = -1;
        score = 0;
      }
    }
    if (best >= 0) found.add(best);
    corners = found;
  }

  void _smooth(int count) {
    _cx.length = count;
    _cy.length = count;
    final bounds = [0, ...corners, count - 1];
    var b = 1;
    for (var i = _posFinal; i < count; i++) {
      while (bounds[b] < i) {
        b++;
      }
      // Stretch [lo, hi] containing i (a corner belongs to the one before).
      final lo = bounds[b - 1], hi = bounds[b];
      _cx[i] = _filtered(_rx, i, lo, hi);
      _cy[i] = _filtered(_ry, i, lo, hi);
    }
    // Final: the window reaches neither a non-final sample nor where a
    // corner may still be found.
    final known = _runBest >= 0 ? _runBest : _scan;
    final settled = math.min(known, _resFinal) - p.kernelK - 1;
    if (settled > _posFinal) _posFinal = settled;
  }

  /// The low-pass value at [i] of [v] within the stretch [lo]..[hi].
  double _filtered(DoubleBuffer v, int i, int lo, int hi) {
    if (i == lo || i == hi || hi - lo < 2) return v[i];
    final w = p.kernel, k = p.kernelK;
    var sum = 0.0;
    final inLo = math.max(lo, i - k), inHi = math.min(hi, i + k);
    for (var m = inLo; m <= inHi; m++) {
      sum += w[m - i + k] * v[m];
    }
    if (i - k < lo) {
      final (a, c) = LineFilters.endFit(v, lo, 1, math.min(p.fit, hi - lo));
      for (var m = i - k; m < lo; m++) {
        final j = (lo - m).toDouble();
        sum += w[m - i + k] * (v[lo] + a * j + c * j * j);
      }
    }
    if (i + k > hi) {
      final (a, c) = LineFilters.endFit(v, hi, -1, math.min(p.fit, hi - lo));
      for (var m = hi + 1; m <= i + k; m++) {
        final j = (m - hi).toDouble();
        sum += w[m - i + k] * (v[hi] + a * j + c * j * j);
      }
    }
    return sum;
  }
}
