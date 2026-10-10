import 'dart:math' as math;
import 'dart:typed_data';

import 'centerline.dart';
import 'outline_sink.dart';

/// Turns a smoothed [Centerline] into a filled outline made of cubic
/// Bézier curves and circular arcs, so its edges stay smooth at any zoom.
///
/// Each side of the stroke is the *envelope* of the circles along the
/// centre line (unlike a plain normal offset, it stays tangent to every
/// circle even where the radius changes), drawn as cubic Hermite curves
/// whose tangents come from the dense samples. Caps are arcs of the end
/// circles and meet the sides tangentially.
///
/// Where the line bends more tightly than its radius (the inner side would
/// fold over), it is split into runs; every run is closed with round caps
/// and wound the same way, so the non-zero fill unions them seamlessly.
class OutlineEmitter {
  OutlineEmitter(this.line, {required this.flatCaps});

  final Centerline line;

  /// Square ends (highlighter) instead of round caps at the stroke's ends.
  final bool flatCaps;

  /// A run boundary is made where curvature × radius exceeds this (1 is
  /// where the inner side folds), or the line turns by more than
  /// [_cuspTurn] radians between neighbouring samples.
  static const double _foldLimit = 0.8;
  static const double _cuspTurn = 0.5;

  /// Output decimation: one cubic spans at most this much turning (radians)
  /// and relative radius change, which keeps it visually exact.
  static const double _maxTurn = 0.2;
  static const double _maxRadiusChange = 0.05;

  /// Writes the outline to [sink].
  void emit(OutlineSink sink) {
    final n = line.length;
    if (n < 2) return;
    final tight = _tightSamples();
    var start = 0;
    for (var i = 1; i < n; i++) {
      if (i == n - 1 || tight[i]) {
        _Run(this, start, i).emit(sink);
        start = i;
      }
    }
  }

  /// Samples where the outline is split into separate runs.
  List<bool> _tightSamples() {
    final n = line.length;
    final x = line.x, y = line.y, r = line.r;
    final tight = List<bool>.filled(n, false);
    for (var i = 1; i < n - 1; i++) {
      final ax = x[i] - x[i - 1], ay = y[i] - y[i - 1];
      final bx = x[i + 1] - x[i], by = y[i + 1] - y[i];
      final turn = math.atan2(ax * by - ay * bx, ax * bx + ay * by).abs();
      tight[i] = turn > _cuspTurn || turn / line.step * r[i] > _foldLimit;
    }
    for (final i in line.corners) {
      tight[i] = true;
    }
    return tight;
  }
}

/// One closed outline between samples [a] and [b] of the centre line.
class _Run {
  _Run(this.owner, this.a, this.b) : count = b - a + 1;

  final OutlineEmitter owner;
  final int a, b, count;

  late final Float64List _tx = Float64List(count), _ty = Float64List(count);
  late final Float64List _lx = Float64List(count), _ly = Float64List(count);
  late final Float64List _rx = Float64List(count), _ry = Float64List(count);

  Centerline get line => owner.line;

  void emit(OutlineSink sink) {
    if (_coveredByOneCircle(sink)) return;
    _envelope();
    final kept = _keptSamples();
    final last = count - 1;
    sink.moveTo(_lx[0], _ly[0]);
    _side(sink, kept, _lx, _ly, forward: true);
    _cap(sink, last, _lx, _ly, _rx, _ry, forward: true);
    _side(sink, kept, _rx, _ry, forward: false);
    _cap(sink, 0, _rx, _ry, _lx, _ly, forward: false);
    sink.close();
  }

  /// A two-sample run whose circles contain one another (or coincide) is
  /// just the bigger circle.
  bool _coveredByOneCircle(OutlineSink sink) {
    if (count != 2) return false;
    final x = line.x, y = line.y, r = line.r;
    final d = math.sqrt(math.pow(x[b] - x[a], 2) + math.pow(y[b] - y[a], 2));
    if (d > (r[b] - r[a]).abs() * 1.05 + 1e-9) return false;
    final i = r[a] >= r[b] ? a : b;
    addCircle(sink, x[i], y[i], r[i]);
    return true;
  }

  /// Unit tangents and the left/right envelope points. Tangents and radius
  /// slopes are central differences inside the run and one-sided at its
  /// ends (a neighbouring run may head elsewhere).
  void _envelope() {
    final x = line.x, y = line.y, r = line.r;
    for (var k = 0; k < count; k++) {
      final i = a + k;
      final i0 = k == 0 ? i : i - 1, i1 = k == count - 1 ? i : i + 1;
      var dx = x[i1] - x[i0], dy = y[i1] - y[i0];
      final d = math.sqrt(dx * dx + dy * dy);
      var slope = 0.0;
      if (d > 0) {
        dx /= d;
        dy /= d;
        slope = ((r[i1] - r[i0]) / d).clamp(-0.95, 0.95);
      } else {
        // Coincident samples: keep the neighbour's direction.
        final j = k == 0 ? 1 : k - 1;
        dx = x[a + j] - x[i];
        dy = y[a + j] - y[i];
        final dj = math.max(1e-12, math.sqrt(dx * dx + dy * dy));
        dx = (k == 0 ? dx : -dx) / dj;
        dy = (k == 0 ? dy : -dy) / dj;
      }
      _tx[k] = dx;
      _ty[k] = dy;
      // Where the radius grows, the envelope touches each circle slightly
      // behind its centre; where it shrinks, slightly ahead.
      final along = -slope * r[i];
      final across = r[i] * math.sqrt(1 - slope * slope);
      _lx[k] = x[i] + along * dx - across * dy;
      _ly[k] = y[i] + along * dy + across * dx;
      _rx[k] = x[i] + along * dx + across * dy;
      _ry[k] = y[i] + along * dy - across * dx;
    }
  }

  /// Run-relative indices where the cubic pieces start and end.
  List<int> _keptSamples() {
    final r = line.r;
    final kept = <int>[0];
    final maxSpan = math.max(4, (8 * r[a] / math.max(line.step, 1e-9)).ceil());
    var turned = 0.0;
    for (var k = 1; k < count - 1; k++) {
      turned += _angle(k - 1, k);
      final from = kept.last;
      final rFrom = r[a + from];
      if (turned + _angle(k, k + 1) > OutlineEmitter._maxTurn ||
          (r[a + k + 1] - rFrom).abs() > OutlineEmitter._maxRadiusChange * rFrom + 1e-3 ||
          k + 1 - from > maxSpan) {
        kept.add(k);
        turned = 0;
      }
    }
    kept.add(count - 1);
    return kept;
  }

  double _angle(int j, int k) => math.acos((_tx[j] * _tx[k] + _ty[j] * _ty[k]).clamp(-1.0, 1.0));

  /// Adds one side as cubic Hermite pieces through the [kept] samples,
  /// along ([forward]) or against the stroke direction.
  void _side(
    OutlineSink sink,
    List<int> kept,
    Float64List px,
    Float64List py, {
    required bool forward,
  }) {
    final h = line.step;
    final order = forward ? kept : kept.reversed.toList();
    for (var m = 1; m < order.length; m++) {
      final j = order[m - 1], k = order[m];
      final span = (k - j) * h / 3; // negative when going backwards
      final (djx, djy) = _derivative(px, py, j);
      final (dkx, dky) = _derivative(px, py, k);
      sink.cubicTo(
        px[j] + djx * span,
        py[j] + djy * span,
        px[k] - dkx * span,
        py[k] - dky * span,
        px[k],
        py[k],
      );
    }
  }

  /// d(side)/d(arc length) at run-relative sample [k]. At the run's ends it
  /// is made tangent to the end circle, so the caps join without a kink.
  (double, double) _derivative(Float64List px, Float64List py, int k) {
    final h = line.step;
    final last = count - 1;
    if (k > 0 && k < last) {
      return ((px[k + 1] - px[k - 1]) / (2 * h), (py[k + 1] - py[k - 1]) / (2 * h));
    }
    final j = k == 0 ? 1 : last - 1;
    final sign = k == 0 ? 1 : -1;
    final sx = sign * (px[j] - px[k]) / h, sy = sign * (py[j] - py[k]) / h;
    final ox = px[k] - line.x[a + k], oy = py[k] - line.y[a + k];
    final len = math.sqrt(ox * ox + oy * oy);
    if (len == 0) return (sx, sy);
    // Oriented along the stroke, like the cap arc meeting it.
    var perpX = -oy / len, perpY = ox / len;
    if (perpX * _tx[k] + perpY * _ty[k] < 0) {
      perpX = -perpX;
      perpY = -perpY;
    }
    final speed = math.sqrt(sx * sx + sy * sy);
    return (perpX * speed, perpY * speed);
  }

  /// Closes the outline around run sample [k], from the [fromX]/[fromY]
  /// side to the [toX]/[toY] side, bulging away from the run.
  void _cap(
    OutlineSink sink,
    int k,
    Float64List fromX,
    Float64List fromY,
    Float64List toX,
    Float64List toY, {
    required bool forward,
  }) {
    final strokeEnd = forward ? b == line.length - 1 : a == 0;
    if (strokeEnd && owner.flatCaps) {
      sink.lineTo(toX[k], toY[k]);
      return;
    }
    final i = a + k;
    final cx = line.x[i], cy = line.y[i];
    final start = math.atan2(fromY[k] - cy, fromX[k] - cx);
    final end = math.atan2(toY[k] - cy, toX[k] - cx);
    final front = forward ? math.atan2(_ty[k], _tx[k]) : math.atan2(-_ty[k], -_tx[k]);
    final clockwise = _mod(end - start);
    final sweep = _mod(front - start) < clockwise ? clockwise : clockwise - 2 * math.pi;
    sink.arc(cx, cy, line.r[i], start, sweep);
  }

  static double _mod(double angle) {
    final m = angle % (2 * math.pi);
    return m < 0 ? m + 2 * math.pi : m;
  }
}
