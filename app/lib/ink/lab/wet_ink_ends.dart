import 'dart:math' as math;

import '../render/flat_ends.dart';
import '../render/growable.dart';

/// Where the overlay's pieces are cut off at flat ends: piece [piece] (the
/// hull of points `piece` and `piece + 1`) is not drawn beyond [line] (on
/// the side its normal faces).
typedef WetCut = ({int piece, EndLine line});

/// The flat ends of the overlay's line (`WetInkModel.segments`), as
/// Flutter's ink draws them (`RibbonEmitter`, `FlatEnds`).
///
/// The overlay's pieces are hulls of circles, so near a flat end the
/// circles of the points within a radius of it reach past the butt cap,
/// where Flutter's runs end square. The butt cap is square to where the
/// line runs over its last half radius before the end (the end sample
/// itself can kink away). The pieces cut are the end's own and those after
/// it that run the end's way (within 60°, as `FlatEnds` decides) while one
/// of their circles still reaches past the cap's line; ink further on that
/// crosses the line (a tight turn back, a loop) stays.
///
/// They are cut off at the cap's line, as Flutter's flat ends' zones are,
/// at the start and at the end, also at the moving pen tip (Flutter draws a
/// live stroke's tip as its committed end).
abstract final class WetInkEnds {
  /// The cuts of the line of [n] points ([x], [y], radii [r], [corners]
  /// as `StrokeShaper.corners`, resampled every [step]) whose pieces from
  /// point [first] on are drawn: at its start if [start] (the stroke's
  /// start is point 0), and at its end.
  static List<WetCut> of(
    DoubleBuffer x,
    DoubleBuffer y,
    List<double> r,
    List<int> corners,
    int n, {
    required int first,
    required double step,
    required bool start,
  }) {
    final e = n - 1;
    final bounds = [
      0,
      for (final c in corners)
        if (c > 0 && c < e) c,
      e,
    ];
    // The butt cap's line at the end i (0 or e) of the stretch lo..hi,
    // facing along the line (or back).
    EndLine cap(int i, int lo, int hi, {bool back = false}) {
      final (tx, ty, s) = _frame(x, y, r, i, lo, hi, step);
      final along = -r[i] * s, sign = back ? -1.0 : 1.0;
      return (px: x[i] + along * tx, py: y[i] + along * ty, nx: sign * tx, ny: sign * ty);
    }

    // Whether piece j runs the way [line] faces (or back) and one of its
    // circles reaches past it.
    bool next(int j, EndLine line, double sign) =>
        _along(x, y, j, j + 1, sign * line.nx, sign * line.ny) &&
        (_reaches(x, y, r, j, line) || _reaches(x, y, r, j + 1, line));

    final cuts = <WetCut>[];
    if (start) {
      final line = cap(0, 0, bounds[1], back: true);
      for (var j = 0; j < e && (j == 0 || next(j, line, -1)); j++) {
        if (j >= first) cuts.add((piece: j, line: line));
      }
    }
    final line = cap(e, bounds[bounds.length - 2], e);
    for (var j = e - 1; j >= first && (j == e - 1 || next(j, line, 1)); j--) {
      cuts.add((piece: j, line: line));
    }
    return cuts;
  }

  /// `RibbonEmitter._frame`: the unit tangent and radius slope at the end
  /// [i] (the first or the last point) of the stretch [lo]..[hi] between
  /// corners, as a flat cap has it.
  static (double, double, double) _frame(
    DoubleBuffer x,
    DoubleBuffer y,
    List<double> r,
    int i,
    int lo,
    int hi,
    double step,
  ) {
    var a = math.max(lo, i - 1), c = math.min(hi, i + 1);
    if (hi - lo >= 3) {
      final k = math.max(1, (0.5 * r[i] / step).ceil());
      (a, c) = i == 0 ? (1, math.min(hi - 1, 1 + k)) : (math.max(lo + 1, i - 1 - k), i - 1);
    }
    var dx = x[c] - x[a], dy = y[c] - y[a];
    var d = math.sqrt(dx * dx + dy * dy);
    // Coincident neighbours (a pinned tip): look one further.
    if (d < 1e-9 && (a > lo || c < hi)) {
      a = math.max(lo, a - 1);
      c = math.min(hi, c + 1);
      dx = x[c] - x[a];
      dy = y[c] - y[a];
      d = math.sqrt(dx * dx + dy * dy);
    }
    if (d < 1e-9) return (1, 0, 0);
    final slope = ((r[c] - r[a]) / d).clamp(-0.9, 0.9);
    return (dx / d, dy / d, slope);
  }

  /// Whether the line from point [a] to [b] runs within 60° of ([tx],
  /// [ty]) (or stands still), as `FlatEnds` decides it.
  static bool _along(DoubleBuffer x, DoubleBuffer y, int a, int b, double tx, double ty) {
    final dx = x[b] - x[a], dy = y[b] - y[a];
    final d = math.sqrt(dx * dx + dy * dy);
    return d < 1e-9 || (dx * tx + dy * ty) >= 0.5 * d;
  }

  /// Whether point [i]'s circle reaches past [line].
  static bool _reaches(DoubleBuffer x, DoubleBuffer y, List<double> r, int i, EndLine line) =>
      (x[i] - line.px) * line.nx + (y[i] - line.py) * line.ny > -r[i];
}
