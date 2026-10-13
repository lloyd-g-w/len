import 'dart:math' as math;

import '../render/flat_ends.dart';
import '../render/growable.dart';

/// Where the overlay's pieces are cut off at flat ends: piece [piece] (the
/// hull of points `piece` and `piece + 1`, or its sweeps) is not drawn
/// beyond [line] (on the side its normal faces).
typedef WetCut = ({int piece, EndLine line});

/// Part of piece [piece] of the overlay, which is drawn as flat nib sweeps
/// (`emitSweep`) instead of the hull of its circles: from cross-section
/// [a] to [b].
typedef WetSweep = ({int piece, CrossSection a, CrossSection b});

/// The flat ends of the overlay's line (`WetInkModel.segments`), as
/// Flutter's ink draws them (`FlatEnds`, `RibbonEmitter`): at the stroke's
/// start and at the end of the line, also at the moving pen tip (Flutter
/// draws a live stroke's tip as its committed end).
///
/// The overlay's pieces are hulls of circles, which reach past a butt cap
/// and round off a curl. Within an end's *zone*, the points before it
/// whose circles touch the end's (at most [of]'s `reach`, and half the
/// line), each piece is instead the area a flat nib sweeps between the
/// cross-sections at its points (the nib turning on a corner too), and the
/// pieces of the zone's last stretch that runs the end's way (within 60°)
/// are cut off at the cap's line. The cap is square to where the line runs
/// over its last half radius before the end (the end sample itself can
/// kink away). Ink further on that crosses the line (a tight turn back, a
/// loop) stays.
abstract final class WetInkEnds {
  /// The cuts and sweeps, in piece order, of the line of [n] points ([x],
  /// [y], radii [r], [corners] as `StrokeShaper.corners`, resampled every
  /// [step]) whose pieces from point [first] on are drawn: at its start if
  /// [start] (point 0 is the stroke's start: the whole line is known), and
  /// at its end. A zone reaches at most [reach] points
  /// (`WetInkShape.flatReach`).
  static ({List<WetCut> cuts, List<WetSweep> sweeps}) of(
    DoubleBuffer x,
    DoubleBuffer y,
    List<double> r,
    List<int> corners,
    int n, {
    required int first,
    required double step,
    required bool start,
    required int reach,
  }) {
    final e = n - 1;
    final bounds = [
      0,
      for (final c in corners)
        if (c > 0 && c < e) c,
      e,
    ];
    // The tangent and radius slope at point i of the stretch lo..hi, as
    // `RibbonEmitter` has them (a flat cap's at the line's ends).
    (double, double, double) frame(int i, int lo, int hi) =>
        _frame(x, y, r, i, lo, hi, step, end: (i == 0 && start) || i == e);
    EndLine cap(int i, int lo, int hi, {bool back = false}) {
      final (tx, ty, s) = frame(i, lo, hi);
      final along = -r[i] * s, sign = back ? -1.0 : 1.0;
      return (px: x[i] + along * tx, py: y[i] + along * ty, nx: sign * tx, ny: sign * ty);
    }

    // The offset points at i, as `RibbonEmitter._offsets`.
    CrossSection section(int i, int lo, int hi) {
      final (tx, ty, s) = frame(i, lo, hi);
      final along = -r[i] * s, across = r[i] * math.sqrt(1 - s * s);
      final ox = x[i] + along * tx, oy = y[i] + along * ty;
      return (
        cx: x[i],
        cy: y[i],
        lx: ox - across * ty,
        ly: oy + across * tx,
        rx: ox + across * ty,
        ry: oy - across * tx,
      );
    }

    bool touches(int k, int end) {
      final dx = x[k] - x[end], dy = y[k] - y[end], d = r[k] + r[end];
      return dx * dx + dy * dy <= d * d;
    }

    // The zones (`FlatEnds.of`): the start's, points 0..to (0..clipTo cut
    // off at its cap), and the end's, from..e (clipFrom..e). A whole line
    // of fewer than four points has none: it is one run between its butt
    // caps, which its sweeps are too.
    final startLine = start ? cap(0, 0, bounds[1], back: true) : null;
    final endLine = cap(e, bounds[bounds.length - 2], e);
    var to = 0, clipTo = 0, from = e, clipFrom = e;
    if (start && n < 4) {
      from = 0;
    } else {
      if (startLine != null) {
        final most = math.min(e ~/ 2, reach);
        while (to < most && touches(to + 1, 0)) {
          to++;
        }
        while (clipTo < to && _along(x, y, clipTo, clipTo + 1, -startLine.nx, -startLine.ny)) {
          clipTo++;
        }
      }
      final most = start ? math.min(e - e ~/ 2, reach) : reach;
      while (e - from < most && from > 0 && touches(from - 1, e)) {
        from--;
      }
      clipFrom = e;
      while (clipFrom > from && _along(x, y, clipFrom - 1, clipFrom, endLine.nx, endLine.ny)) {
        clipFrom--;
      }
    }

    final cuts = <WetCut>[], sweeps = <WetSweep>[];
    var b = 1; // piece j lies in the stretch bounds[b − 1]..bounds[b]
    for (var j = first; j < e; j++) {
      while (bounds[b] <= j) {
        b++;
      }
      final lo = bounds[b - 1], hi = bounds[b];
      final inStart = startLine != null && j + 1 <= to, inEnd = j >= from;
      // A corner in a zone: the nib turns on it (`RibbonEmitter._walk`).
      if (inEnd && j == lo && lo > 0) {
        final c = section(lo, bounds[b - 2], lo);
        sweeps.add((piece: j, a: c, b: section(lo, lo, hi)));
      }
      if (inStart || inEnd) {
        sweeps.add((piece: j, a: section(j, lo, hi), b: section(j + 1, lo, hi)));
      }
      if (inStart && j + 1 == hi && hi < e && hi < from) {
        sweeps.add((piece: j, a: section(hi, lo, hi), b: section(hi, hi, bounds[b + 1])));
      }
      // A hull's round end at the line's ends goes too.
      final hull = !inStart && !inEnd;
      if (startLine != null && (j + 1 <= clipTo || (j == 0 && hull))) {
        cuts.add((piece: j, line: startLine));
      }
      if (j >= clipFrom || (j == e - 1 && hull)) cuts.add((piece: j, line: endLine));
    }
    return (cuts: cuts, sweeps: sweeps);
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

  /// Whether the line from point [a] to [b] runs within 60° of ([tx],
  /// [ty]) (or stands still), as `FlatEnds` decides it.
  static bool _along(DoubleBuffer x, DoubleBuffer y, int a, int b, double tx, double ty) {
    final dx = x[b] - x[a], dy = y[b] - y[a];
    final d = math.sqrt(dx * dx + dy * dy);
    return d < 1e-9 || (dx * tx + dy * ty) >= 0.5 * d;
  }
}
