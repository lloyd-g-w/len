import 'dart:math' as math;

import 'capsule_emitter.dart';
import 'flat_ends.dart';
import 'growable.dart';
import 'outline_sink.dart';

part 'ribbon_emitter_geometry.dart';
part 'ribbon_emitter_runs.dart';

/// The centre line a [RibbonEmitter] outlines: positions and radii of
/// uniformly spaced samples, and the corners that split it into stretches.
abstract interface class RibbonLine {
  DoubleBuffer get x;
  DoubleBuffer get y;
  DoubleBuffer get r;
  int get length;
  List<int> get corners;
}

/// The first [length] samples of [line] (live ink with the stabiliser on
/// shows only the final part of its line, `StrokeShaper.liveLength`).
class RibbonPrefix implements RibbonLine {
  RibbonPrefix(this.line, this.length)
    : corners = [
        for (final c in line.corners)
          if (c < length - 1) c,
      ];

  final RibbonLine line;
  @override
  final int length;
  @override
  final List<int> corners;
  @override
  DoubleBuffer get x => line.x;
  @override
  DoubleBuffer get y => line.y;
  @override
  DoubleBuffer get r => line.r;
}

/// Where the live outline's frozen part ends: the sample, and whether the
/// outline continues there with a straight cut (inside a run) rather than
/// a new run's cap.
typedef RibbonCursor = ({int at, bool cut});

/// Turns a centre line with radii into a filled outline made of few, smooth
/// contours.
///
/// The outline of a variable-width stroke is the envelope of its circles:
/// each side is offset from the centre line by the radius, along the
/// normal tilted by the radius slope (`c + r(−r′t ± √(1−r′²)n)`). A *run* of
/// samples becomes one closed contour — left side forward, a round cap,
/// right side back, a round cap — whose sides are cubic Béziers fitted to
/// the offset points (tangent at every join, a few verbs per pen-width of
/// length), so the edges are smooth at any zoom and the GPU fills one
/// simple contour instead of thousands of capsules.
///
/// Runs end where the envelope would fold: at corners (cusps, where the
/// line doubles back) and wherever a side would run backwards (a bend
/// tighter than the radius). Such segments are drawn as exact capsules
/// (the hull of their two circles). Neighbouring contours overlap in their
/// round caps, and all wind the same way, so the non-zero fill unions them.
///
/// Every decision is made from samples at most two ahead, and runs are cut
/// into pieces at fixed sample indices (multiples of [block]), so the live
/// stroke can [freeze] final pieces once and only rebuild its tail.
class RibbonEmitter {
  RibbonEmitter(this.line, {required this.flatCaps, required this.width, required double step})
    : tolerance = toleranceFor(width),
      block = math.max(16, (24 / step).ceil()),
      _endReach = endReachFor(width, step),
      _step = step;

  final RibbonLine line;
  final bool flatCaps;
  final double width;

  /// Largest distance between a fitted side and its offset points (world
  /// units). The cubic that reaches into a live stroke's not-yet-final tip
  /// is refitted every frame and may move by up to twice this along its
  /// whole span (up to [_maxSpan] samples), so it is kept well below a
  /// physical pixel even when zoomed in 8×.
  final double tolerance;

  /// The [tolerance] for a pen [width] wide.
  static double toleranceFor(double width) => math.min(0.004, 0.002 * (1 + width));

  /// Runs are split into pieces at sample indices that are multiples of
  /// this (forced curve keys, where the live stroke may cut).
  final int block;

  static const int _maxSpan = 32;

  final double _step;

  /// With [flatCaps], how far (samples) an end's zone may reach
  /// (`FlatEnds`): two widths.
  final int _endReach;

  /// How far (samples [step] apart) a flat end's zone may reach on a line
  /// [width] wide: two widths.
  static int endReachFor(double width, double step) => (2 * width / step).ceil();

  /// Within a run, a side may not run backwards by more than this many
  /// centre-line steps per step (a mild fold of the inner side, at a bend
  /// tighter than the radius, is fine: the non-zero fill still covers
  /// exactly the union of the circles, see test/ribbon_exactness_test.dart;
  /// at 2 the long, smooth tight bends a strong stabiliser makes of small
  /// loops left slivers uncovered).
  static double foldAdvance = -1;

  /// Cosine of the largest tangent turn per sample within a run.
  static double foldCos = -0.5;

  /// Emits the whole outline from [from] to the end of the line. With
  /// [cut], the outline starts at [from] with a straight cut (the frozen
  /// part of a live stroke ends there). The line's last sample is an end,
  /// also a live stroke's moving tip: a flat pen's tip is drawn as its
  /// committed end will be (`FlatEnds`), so it does not turn round and
  /// square from frame to frame as the last pieces fold or not.
  void emit(OutlineSink sink, {RibbonCursor from = (at: 0, cut: false)}) =>
      _walk(sink, from, null, ended: true);

  /// Emits the pieces from [from] whose geometry only depends on the first
  /// [finalCount] samples, each as its own contour; returns where the
  /// frozen part now ends. With [flatCaps], none that a flat end's zone at
  /// the tip [shown] samples long (the live line, by default all of it)
  /// may cover, so the tail draws the tip's zone whole, as [emit] does.
  RibbonCursor freeze(OutlineSink sink, RibbonCursor from, int finalCount, {int? shown}) {
    final tip = (shown ?? line.length) - 1;
    final limit = flatCaps ? math.min(finalCount, tip - _endReach) : finalCount;
    return _walk(sink, from, limit, ended: false);
  }

  RibbonCursor _walk(OutlineSink sink, RibbonCursor from, int? limit, {required bool ended}) {
    final n = line.length;
    final bounds = [0, ...line.corners, n - 1];
    final ends = _flatEnds(bounds, limit: limit, ended: ended);
    OutlineSink to(int a, int b) => ends?.clip(sink, a, b, tolerance) ?? sink;
    // Freezing waits until the start's zone is known.
    if (ends != null && !ends.settled && limit != null) return from;
    var b = 1;
    var i = from.at;
    var cut = from.cut;
    while (i < n - 1) {
      while (bounds[b] <= i) {
        b++;
      }
      final lo = bounds[b - 1], hi = bounds[b];
      if (limit != null && i + 3 >= limit) break;
      // A corner within a flat end's zone: the nib turns on it.
      if (i == lo && lo > 0 && ends != null && ends.covers(lo, lo)) {
        _sweep(to(lo, lo), lo, _offsets(lo, bounds[b - 2], lo), lo, _offsets(lo, lo, hi));
      }
      if (_folded(i, lo, hi)) {
        if (ends != null && ends.covers(i, i + 1)) {
          _sweep(to(i, i + 1), i, _offsets(i, lo, hi), i + 1, _offsets(i + 1, lo, hi));
        } else {
          _capsule(sink, i);
        }
        i++;
        cut = false;
        continue;
      }
      // A run from i to its end j.
      var j = i + 1;
      var open = false; // not known yet where the run ends
      while (j < hi) {
        if (limit != null && j + 3 >= limit) {
          open = true;
          break;
        }
        if (_folded(j, lo, hi)) break;
        j++;
      }
      // Pieces split where a flat end's zone begins or ends, and when
      // freezing, at multiples of [block]; a piece in a zone has straight
      // cuts for ends.
      var p = i;
      while (p < j) {
        var q = ends?.split(p, j) ?? j;
        if (limit != null) q = math.min(q, (p ~/ block + 1) * block);
        if (q == j && open) break;
        final zone = ends != null && ends.covers(p, q);
        _run(
          to(p, q),
          p,
          q,
          lo,
          hi,
          startCut: zone || (p == i ? cut : true),
          endCut: zone || q < j,
        );
        p = q;
      }
      if (limit != null && (p < j || open)) return (at: p, cut: p > i || cut);
      i = j;
      cut = false;
    }
    return (at: i, cut: cut);
  }

  /// The first sample of the end's flat zone (the line's length without
  /// one): its pieces are drawn differently once the line has ended.
  int endZoneFrom() => _flatEnds([0, ...line.corners, line.length - 1])?.endFrom ?? line.length;

  FlatEnds? _flatEnds(List<int> bounds, {int? limit, bool ended = true}) => FlatEnds.of(
    line,
    flatCaps: flatCaps,
    reach: _endReach,
    endLine: (i) => _endLine(i, bounds),
    limit: limit,
    ended: ended,
  );

  /// The line of the butt cap at the first or last sample [i] (the offset
  /// points tilt with the radius slope), facing away from the line.
  EndLine _endLine(int i, List<int> bounds) {
    final (tx, ty, s) = i == 0 ? _frame(0, 0, bounds[1]) : _frame(i, bounds[bounds.length - 2], i);
    final along = -line.r[i] * s, sign = i == 0 ? -1.0 : 1.0;
    return (px: line.x[i] + along * tx, py: line.y[i] + along * ty, nx: sign * tx, ny: sign * ty);
  }

  /// The area a flat nib sweeps from cross-section [a] to [b].
  void _sweep(OutlineSink sink, int i, _Offsets a, int j, _Offsets b) =>
      emitSweep(sink, _section(i, a), _section(j, b), tolerance);

  CrossSection _section(int i, _Offsets o) =>
      (cx: line.x[i], cy: line.y[i], lx: o.lx, ly: o.ly, rx: o.rx, ry: o.ry);
}
