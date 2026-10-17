import 'dart:math' as math;
import 'dart:ui';

import 'package:len/domain/stroke.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import '../inklab/metrics/outline_geometry.dart';
import '../inklab/metrics/smoothing.dart';
import 'mouse_writing.dart';

/// How smooth committed ink is against the path the hand made (screen px):
/// the measures of `test/mouse_ink_smoothness_test.dart`.
class Roughness {
  /// Edge bumps: the largest / RMS residual of each edge against a local
  /// parabola over ±2 px (short bumps) and over ±6 px (waves).
  double bump2 = 0, bump2Rms = 0, wave6 = 0, wave6Rms = 0;

  /// Long waves: the largest residual of the centre line against a
  /// parabola over ±15 px (a whole-pixel step on a nearly level line).
  double wave15 = 0;

  /// How far the centre line keeps off the tips of cusps (px): rounded off.
  double cusp = 0;

  /// The centre line's turning: how much it changes per px (rad/px; a
  /// smooth curve's is small), and the largest kink (°, against a
  /// parabola over ±3 px).
  double wobble = 0, kink = 0;

  /// Widths across straight lines: relative spread (std / mean, %) and the
  /// largest swelling or pinching (max − min, % of the pen's width).
  double widthSd = 0, widthRange = 0;

  /// Farthest the centre line strays from the true path (px).
  double drift = 0;

  /// Ink at the ends beyond the true path dilated by the pen's radius (px).
  double endExcess = 0;

  int _n2 = 0, _n6 = 0;
  double _s2 = 0, _s6 = 0, _wobbleSum = 0, _length = 0;

  void _finish() {
    bump2Rms = _n2 == 0 ? 0 : math.sqrt(_s2 / _n2);
    wave6Rms = _n6 == 0 ? 0 : math.sqrt(_s6 / _n6);
    wobble = _length == 0 ? 0 : _wobbleSum / _length;
  }

  @override
  String toString() =>
      'bump2 ${_f(bump2)} (rms ${_f(bump2Rms)})  wave6 ${_f(wave6)} (rms ${_f(wave6Rms)})  '
      'wave15 ${_f(wave15)}  cusp ${_f(cusp)}  wobble ${_f(wobble, 4)}  kink ${_f(kink, 1)}°  width sd ${_f(widthSd, 1)}% '
      'range ${_f(widthRange, 1)}%  drift ${_f(drift)}  ends ${_f(endExcess)}';
}

String _f(double v, [int d = 2]) => v.toStringAsFixed(d);

/// Measures the committed strokes of [replay] (drawn at [zoom]) against
/// [truths] (screen px). [straight]: the truths are straight lines, whose
/// widths are measured too.
Roughness roughnessOf(
  ReplayResult replay,
  List<TruePath> truths, {
  required double zoom,
  bool straight = false,
}) {
  final out = Roughness();
  final strokes = replay.strokes;
  if (strokes.length != truths.length) {
    throw StateError('${strokes.length} strokes for ${truths.length} paths');
  }
  for (final (k, s) in strokes.indexed) {
    _measure(out, s, truths[k], zoom, straight: straight);
  }
  out._finish();
  return out;
}

void _measure(Roughness out, Stroke s, TruePath truth, double zoom, {required bool straight}) {
  final line = StrokeOutline.centerline(s.points, StrokeRenderer.specFor(s.width, s.style));
  if (line == null || line.length < 8) return;
  final c = [for (var i = 0; i < line.length; i++) Offset(line.x[i], line.y[i]) * zoom];
  final r = [for (var i = 0; i < line.length; i++) line.r[i] * zoom];
  final step = line.step * zoom;
  final radius = s.width * zoom / 2;
  // Skipped: the ends, and around cusps.
  final endReach = 2 * radius + 3;
  final along = [0.0];
  for (var i = 1; i < c.length; i++) {
    along.add(along.last + (c[i] - c[i - 1]).distance);
  }
  final total = along.last;
  bool used(int i) =>
      along[i] > endReach &&
      total - along[i] > endReach &&
      truth.cusps.every((p) => (c[i] - p).distance > 4 + radius);

  // Edge bumps.
  final n = normals(c);
  final m2 = math.max(2, (2 / step).round()), m6 = math.max(3, (6 / step).round());
  for (final side in [1.0, -1.0]) {
    final ex = [for (var i = 0; i < c.length; i++) c[i].dx + side * r[i] * n[i].dx];
    final ey = [for (var i = 0; i < c.length; i++) c[i].dy + side * r[i] * n[i].dy];
    for (final (m, wave) in [(m2, false), (m6, true)]) {
      final sx = savitzkyGolay(ex, m), sy = savitzkyGolay(ey, m);
      for (var i = m; i < c.length - m; i++) {
        if (!used(i)) continue;
        final d = ((ex[i] - sx[i]) * n[i].dx + (ey[i] - sy[i]) * n[i].dy).abs();
        if (wave) {
          out.wave6 = math.max(out.wave6, d);
          out._s6 += d * d;
          out._n6++;
        } else {
          out.bump2 = math.max(out.bump2, d);
          out._s2 += d * d;
          out._n2++;
        }
      }
    }
  }

  // Long waves of the centre line.
  final m15 = math.max(5, (15 / step).round());
  final cx = savitzkyGolay([for (final p in c) p.dx], m15);
  final cy = savitzkyGolay([for (final p in c) p.dy], m15);
  for (var i = m15; i < c.length - m15; i++) {
    if (!used(i) || !used(i - m15) || !used(i + m15)) continue;
    final d = ((c[i].dx - cx[i]) * n[i].dx + (c[i].dy - cy[i]) * n[i].dy).abs();
    out.wave15 = math.max(out.wave15, d);
  }
  for (final tip in truth.cusps) {
    out.cusp = math.max(out.cusp, _distanceTo(c, tip));
  }

  // Turning, every px.
  final even = <Offset>[c.first];
  final evenUsed = <bool>[used(0)];
  var next = 1.0;
  for (var i = 1; i < c.length; i++) {
    while (along[i] >= next) {
      final t = (next - along[i - 1]) / math.max(1e-9, along[i] - along[i - 1]);
      even.add(Offset.lerp(c[i - 1], c[i], t)!);
      evenUsed.add(used(i));
      next += 1;
    }
  }
  final turns = [
    0.0,
    for (var i = 1; i + 1 < even.length; i++) turn(even[i - 1], even[i], even[i + 1]),
    0.0,
  ];
  final smooth = savitzkyGolay(turns, 3);
  for (var i = 2; i + 2 < even.length; i++) {
    if (!evenUsed[i]) continue;
    out._wobbleSum += (turns[i] - turns[i - 1]).abs();
    out._length += 1;
    out.kink = math.max(out.kink, (turns[i] - smooth[i]).abs() * 180 / math.pi);
  }

  // Drift from the true path.
  for (final p in c) {
    out.drift = math.max(out.drift, _distanceTo(truth.points, p));
  }

  // The outline: ink beyond the ideal band at the ends; widths across
  // straight lines.
  final outline = outlineOf(
    s.points,
    tool: s.tool,
    width: s.width,
    style: s.style,
    complete: true,
    map: (o) => o * zoom,
  );
  final a = truth.points.first, b = truth.points.last;
  for (final contour in outline.contours) {
    for (final p in contour) {
      if ((p - a).distance > 2 * radius + 2 && (p - b).distance > 2 * radius + 2) continue;
      out.endExcess = math.max(out.endExcess, _distanceTo(truth.points, p) - radius);
    }
  }
  if (straight) _widths(out, outline.contours, a, b, 2 * radius);
}

/// Widths of [contours] across the straight line [a]–[b], every 0.5 px
/// away from its ends.
void _widths(Roughness out, List<List<Offset>> contours, Offset a, Offset b, double width) {
  final dir = (b - a) / (b - a).distance;
  final normal = Offset(-dir.dy, dir.dx);
  final widths = <double>[];
  final length = (b - a).distance;
  for (var d = 2 * width + 4; d < length - 2 * width - 4; d += 0.5) {
    final o = a + dir * d;
    var lo = double.infinity, hi = -double.infinity;
    for (final contour in contours) {
      for (var i = 0; i < contour.length; i++) {
        final p = contour[i], q = contour[(i + 1) % contour.length];
        final pa = (p - o).dx * dir.dx + (p - o).dy * dir.dy;
        final qa = (q - o).dx * dir.dx + (q - o).dy * dir.dy;
        if ((pa > 0) == (qa > 0) || pa == qa) continue;
        final t = pa / (pa - qa);
        final x = Offset.lerp(p, q, t)! - o;
        final across = x.dx * normal.dx + x.dy * normal.dy;
        lo = math.min(lo, across);
        hi = math.max(hi, across);
      }
    }
    if (hi > lo) widths.add(hi - lo);
  }
  if (widths.isEmpty) return;
  final mean = widths.reduce((x, y) => x + y) / widths.length;
  final variance = widths.map((w) => (w - mean) * (w - mean)).reduce((x, y) => x + y);
  final sd = math.sqrt(variance / widths.length);
  out.widthSd = math.max(out.widthSd, 100 * sd / mean);
  out.widthRange = math.max(
    out.widthRange,
    100 * (widths.reduce(math.max) - widths.reduce(math.min)) / width,
  );
}

double _distanceTo(List<Offset> path, Offset p) {
  var best = double.infinity;
  for (var i = 0; i + 1 < path.length; i += 1) {
    final a = path[i], b = path[i + 1];
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    final t = l2 == 0 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
    best = math.min(best, (p - (a + ab * t)).distance);
  }
  return best;
}

/// How far live ink trails the mouse (screen px): per frame drawn while
/// the mouse moved, the distance from its newest event to the end of the
/// ink shown. Median and 90th percentile.
({double median, double p90}) lagOf(
  ReplayResult replay,
  List<List<MouseEvent>> events, {
  required double zoom,
}) {
  final at = <int, Offset>{
    for (final stroke in events)
      for (final e in stroke) e.timeUs: e.position,
  };
  final lags = <double>[];
  int? previous;
  for (final f in replay.frames) {
    if (!f.drawing || f.points.length < 2) {
      previous = null;
      continue;
    }
    final moved = previous != null && previous != f.newestEventUs;
    previous = f.newestEventUs;
    if (!moved) continue;
    final mouse = at[f.newestEventUs];
    if (mouse == null) continue;
    final spec = StrokeRenderer.specFor(replay.pen.width, f.style);
    final line = StrokeOutline.centerline(f.points, spec, complete: false);
    if (line == null || line.live < 1) continue;
    final tip = Offset(line.x[line.live - 1], line.y[line.live - 1]) * zoom;
    lags.add((tip - mouse).distance);
  }
  if (lags.isEmpty) return (median: 0, p90: 0);
  lags.sort();
  return (median: lags[lags.length ~/ 2], p90: lags[(lags.length * 0.9).floor()]);
}
