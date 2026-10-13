import 'dart:math' as math;

import '../render/flat_ends.dart';
import '../render/growable.dart';
import '../render/ribbon_emitter.dart';

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
/// They are cut off at the cap's line, as Flutter's flat ends' zones are
/// (at the start always, at the end once Flutter has committed the
/// stroke). Before
/// then the pen tip's run simply ends at its cross-section, so each piece
/// at the tip is cut off at the cross-section ahead of it instead (a turn
/// at the tip keeps its outer side), back to a piece Flutter draws round
/// (a fold, `RibbonEmitter`): a run before a fold ends in a round cap.
abstract final class WetInkEnds {
  /// The cuts of the line of [n] points ([x], [y], radii [r], [corners]
  /// as `StrokeShaper.corners`, resampled every [step]) whose pieces from
  /// point [first] on are drawn: at its start if [start] (the stroke's
  /// start is point 0), and at its end (the committed stroke's end if
  /// [ended]).
  static List<WetCut> of(
    DoubleBuffer x,
    DoubleBuffer y,
    List<double> r,
    List<int> corners,
    int n, {
    required int first,
    required double step,
    required bool start,
    required bool ended,
  }) {
    final e = n - 1;
    final bounds = [
      0,
      for (final c in corners)
        if (c > 0 && c < e) c,
      e,
    ];
    // The cross-section at point i of the stretch lo..hi, facing along the
    // line (or back).
    EndLine section(int i, int lo, int hi, {bool back = false}) {
      final (tx, ty, s) = _frame(x, y, r, i, lo, hi, step, end: i == 0 || i == e);
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
      final line = section(0, 0, bounds[1], back: true);
      for (var j = 0; j < e && (j == 0 || next(j, line, -1)); j++) {
        if (j >= first) cuts.add((piece: j, line: line));
      }
    }
    final line = section(e, bounds[bounds.length - 2], e);
    var b = bounds.length - 1;
    for (var j = e - 1; j >= first && (j == e - 1 || next(j, line, 1)); j--) {
      if (ended) {
        cuts.add((piece: j, line: line));
        continue;
      }
      while (bounds[b - 1] > j) {
        b--;
      }
      final lo = bounds[b - 1], hi = bounds[b];
      if (_folded(x, y, r, j, lo, hi, e, step)) break;
      cuts.add((piece: j, line: j + 1 == e ? line : section(j + 1, lo, hi)));
    }
    return cuts;
  }

  /// `RibbonEmitter._frame`: the unit tangent and radius slope at point
  /// [i] of the stretch [lo]..[hi] between corners; at an [end] of the
  /// line as a flat cap has it.
  static (double, double, double) _frame(
    DoubleBuffer x,
    DoubleBuffer y,
    List<double> r,
    int i,
    int lo,
    int hi,
    double step, {
    required bool end,
  }) {
    var a = math.max(lo, i - 1), c = math.min(hi, i + 1);
    if (end && hi - lo >= 3) {
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

  /// `RibbonEmitter._folded`: whether Flutter draws piece [i] of the
  /// stretch [lo]..[hi] of the line ending at point [e] as a round capsule
  /// (the samples coincide, a side runs far backwards, or the line turns
  /// too sharply).
  static bool _folded(
    DoubleBuffer x,
    DoubleBuffer y,
    List<double> r,
    int i,
    int lo,
    int hi,
    int e,
    double step,
  ) {
    final ux = x[i + 1] - x[i], uy = y[i + 1] - y[i];
    final u = math.sqrt(ux * ux + uy * uy);
    if (u < 1e-9) return true;
    final (atx, aty, sa) = _frame(x, y, r, i, lo, hi, step, end: i == 0);
    final (btx, bty, sb) = _frame(x, y, r, i + 1, lo, hi, step, end: i + 1 == e);
    // The sides' offset points: along the tangent by −r·s, across by
    // r·√(1 − s²).
    final aAlong = -r[i] * sa, aAcross = r[i] * math.sqrt(1 - sa * sa);
    final bAlong = -r[i + 1] * sb, bAcross = r[i + 1] * math.sqrt(1 - sb * sb);
    final min = RibbonEmitter.foldAdvance * u * u;
    for (final side in const [1.0, -1.0]) {
      final ax = x[i] + aAlong * atx - side * aAcross * aty;
      final ay = y[i] + aAlong * aty + side * aAcross * atx;
      final bx = x[i + 1] + bAlong * btx - side * bAcross * bty;
      final by = y[i + 1] + bAlong * bty + side * bAcross * btx;
      if ((bx - ax) * ux + (by - ay) * uy < min) return true;
    }
    return atx * btx + aty * bty < RibbonEmitter.foldCos;
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
