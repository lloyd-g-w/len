import 'dart:math' as math;

import 'half_plane_clip.dart';
import 'outline_sink.dart';
import 'ribbon_emitter.dart';

/// The line of a flat end's butt cap: through ([px], [py]), facing away
/// from the line along ([nx], [ny]) (a unit vector).
typedef EndLine = ({double px, double py, double nx, double ny});

/// The *zones* of a line's flat ends (butt caps: the highlighter, the pen's
/// flat ends), where `RibbonEmitter` draws the ink as a flat nib leaves it.
///
/// A butt cap squares off the run it ends. Over a curl tighter than the
/// ink's width, though, the last pieces fold back on each other, and folds
/// are drawn as round pieces (capsules, the caps of runs) that bulge past
/// the end and round it off. Within an end's zone, the samples before it
/// whose circles still touch the end's (at most [reach] samples, and half
/// the line), the ink is instead the sweep of the cross-sections, the
/// segments across the line at each sample, as a flat nib would leave it:
/// runs end in straight cuts, and folds, corners included, are filled
/// between consecutive cross-sections. Nothing round is left to bulge past
/// the end.
///
/// A nib still turning as it stops sweeps a little past its last
/// cross-section, though, so the pieces of the zone's last stretch that
/// runs the end's way (within 60° of it) are cut off at the end's line
/// (`HalfPlaneClip`). Ink further back that crosses the line, the body
/// before a tight turn or a loop, is the stroke's own and stays.
class FlatEnds {
  FlatEnds._({
    required this.startTo,
    required this.startClipTo,
    required this.startLine,
    required this.endFrom,
    required this.endClipFrom,
    required this.endLine,
    required this.settled,
  });

  /// The zones of [line]'s ends, which reach at most [reach] samples (null
  /// without [flatCaps]); [endLine] gives the butt cap's line at the first
  /// or the last sample. The end's zone only once the line has [ended] (a
  /// live stroke's tip keeps its pieces until pen-up). With [limit]
  /// (freezing a live stroke: samples from [limit] on are not final) the
  /// start's zone is [settled] once no later sample can change it.
  static FlatEnds? of(
    RibbonLine line, {
    required bool flatCaps,
    required int reach,
    required EndLine Function(int i) endLine,
    int? limit,
    bool ended = true,
  }) {
    final n = line.length;
    if (!flatCaps || n < 4) return null;
    // Start: samples 0..to, within half the line (when freezing, half the
    // final line: what live ink shows of it may end there).
    final startCap = math.min((math.min(n, limit ?? n) - 1) ~/ 2, reach);
    var to = 0;
    while (to < startCap && _touches(line, to + 1, 0)) {
      to++;
    }
    // Ended by a sample that does not touch, or by the reach; not by the
    // half line, which grows; and decided from final samples only.
    final settled = (to < startCap || to == reach) && (limit == null || to + 1 < limit);
    final start = endLine(0);
    var clipTo = 0;
    while (clipTo < to && _along(line, clipTo, clipTo + 1, -start.nx, -start.ny)) {
      clipTo++;
    }
    if (!ended) {
      return FlatEnds._(
        startTo: to,
        startClipTo: clipTo,
        startLine: start,
        endFrom: n,
        endClipFrom: n,
        endLine: null,
        settled: settled,
      );
    }
    // End: samples from..n − 1 (never before the start's zone ends).
    final endCap = math.min(n - 1 - (n - 1) ~/ 2, reach);
    var k = 0;
    while (k < endCap && _touches(line, n - 2 - k, n - 1)) {
      k++;
    }
    final from = n - 1 - k, end = endLine(n - 1);
    var clipFrom = n - 1;
    while (clipFrom > from && _along(line, clipFrom - 1, clipFrom, end.nx, end.ny)) {
      clipFrom--;
    }
    return FlatEnds._(
      startTo: to,
      startClipTo: clipTo,
      startLine: start,
      endFrom: from,
      endClipFrom: clipFrom,
      endLine: end,
      settled: settled,
    );
  }

  /// The start's zone: samples 0..[startTo]; of them, 0..[startClipTo]
  /// are cut off at [startLine].
  final int startTo, startClipTo;
  final EndLine startLine;

  /// The end's zone: samples [endFrom]..the last ([RibbonLine.length]
  /// before the line has ended: none yet); of them, [endClipFrom]..the
  /// last are cut off at [endLine].
  final int endFrom, endClipFrom;
  final EndLine? endLine;

  /// Whether the start's zone is final (see [of]).
  final bool settled;

  /// Whether the piece over samples [a]..[b] lies in a zone.
  bool covers(int a, int b) => b <= startTo || a >= endFrom;

  /// [sink], cutting the piece over samples [a]..[b] off at the ends'
  /// lines it must stay behind, flattened to within [tolerance].
  OutlineSink clip(OutlineSink sink, int a, int b, double tolerance) {
    var s = sink;
    final start = startLine, end = endLine;
    if (b <= startClipTo) s = HalfPlaneClip(s, start, tolerance);
    if (end != null && a >= endClipFrom) s = HalfPlaneClip(s, end, tolerance);
    return s;
  }

  /// Where a piece from [p] that would run to [j] must stop: at a zone's
  /// boundary in between.
  int split(int p, int j) {
    var q = j;
    for (final at in [startClipTo, startTo, endFrom, endClipFrom]) {
      if (at > p && at < q) q = at;
    }
    return q;
  }

  static bool _touches(RibbonLine line, int k, int e) {
    final dx = line.x[k] - line.x[e], dy = line.y[k] - line.y[e];
    final reach = line.r[k] + line.r[e];
    return dx * dx + dy * dy <= reach * reach;
  }

  /// Whether the line from sample [a] to [b] runs within 60° of
  /// ([tx], [ty]) (or stands still).
  static bool _along(RibbonLine line, int a, int b, double tx, double ty) {
    final dx = line.x[b] - line.x[a], dy = line.y[b] - line.y[a];
    final d = math.sqrt(dx * dx + dy * dy);
    return d < 1e-9 || (dx * tx + dy * ty) >= 0.5 * d;
  }
}

/// A cross-section of the line: its centre ([cx], [cy]) and its ends on
/// the left ([lx], [ly]) and right ([rx], [ry]).
typedef CrossSection = ({double cx, double cy, double lx, double ly, double rx, double ry});

/// Emits the area a flat nib sweeps from cross-section [a] to [b], wound
/// like every outline contour. The nib turns as it moves, so the way is
/// split into steps short enough that its ends' arcs stay within
/// [tolerance] of their chords; each step is two triangles meeting where
/// the sections cross (the nib turned about a point on it), else the hull
/// of both.
void emitSweep(OutlineSink sink, CrossSection a, CrossSection b, double tolerance) {
  final la = math.atan2(a.ly - a.cy, a.lx - a.cx), lb = math.atan2(b.ly - b.cy, b.lx - b.cx);
  final ra = math.atan2(a.ry - a.cy, a.rx - a.cx), rb = math.atan2(b.ry - b.cy, b.rx - b.cx);
  final dl = _wrap(lb - la), dr = _wrap(rb - ra);
  final reach = [
    _len(a.lx - a.cx, a.ly - a.cy),
    _len(b.lx - b.cx, b.ly - b.cy),
    _len(a.rx - a.cx, a.ry - a.cy),
    _len(b.rx - b.cx, b.ry - b.cy),
  ].reduce(math.max);
  final perStep = reach <= tolerance ? math.pi : math.sqrt(8 * tolerance / reach);
  final steps = math.max(1, math.min(64, (math.max(dl.abs(), dr.abs()) / perStep).ceil()));
  CrossSection at(double t) {
    if (t == 0) return a;
    if (t == 1) return b;
    final cx = a.cx + (b.cx - a.cx) * t, cy = a.cy + (b.cy - a.cy) * t;
    final ml = _len(a.lx - a.cx, a.ly - a.cy) * (1 - t) + _len(b.lx - b.cx, b.ly - b.cy) * t;
    final mr = _len(a.rx - a.cx, a.ry - a.cy) * (1 - t) + _len(b.rx - b.cx, b.ry - b.cy) * t;
    final al = la + dl * t, ar = ra + dr * t;
    return (
      cx: cx,
      cy: cy,
      lx: cx + ml * math.cos(al),
      ly: cy + ml * math.sin(al),
      rx: cx + mr * math.cos(ar),
      ry: cy + mr * math.sin(ar),
    );
  }

  var from = a;
  for (var k = 1; k <= steps; k++) {
    final to = at(k / steps);
    _step(sink, from, to);
    from = to;
  }
}

double _wrap(double a) {
  while (a > math.pi) {
    a -= 2 * math.pi;
  }
  while (a <= -math.pi) {
    a += 2 * math.pi;
  }
  return a;
}

double _len(double x, double y) => math.sqrt(x * x + y * y);

void _step(OutlineSink sink, CrossSection a, CrossSection b) {
  final x = _cross(a.lx, a.ly, a.rx, a.ry, b.lx, b.ly, b.rx, b.ry);
  if (x != null) {
    _polygon(sink, [a.lx, a.ly, b.lx, b.ly, x.$1, x.$2]);
    _polygon(sink, [a.rx, a.ry, b.rx, b.ry, x.$1, x.$2]);
    return;
  }
  _polygon(sink, _hull([a.lx, a.ly, a.rx, a.ry, b.lx, b.ly, b.rx, b.ry]));
}

/// Where segments A and B cross (strictly inside both), or null.
(double, double)? _cross(
  double ax,
  double ay,
  double bx,
  double by,
  double cx,
  double cy,
  double dx,
  double dy,
) {
  final ux = bx - ax, uy = by - ay, vx = dx - cx, vy = dy - cy;
  final den = ux * vy - uy * vx;
  if (den.abs() < 1e-12) return null;
  final t = ((cx - ax) * vy - (cy - ay) * vx) / den;
  final s = ((cx - ax) * uy - (cy - ay) * ux) / den;
  if (t <= 0 || t >= 1 || s <= 0 || s >= 1) return null;
  return (ax + ux * t, ay + uy * t);
}

/// The convex hull of the points (x0, y0, x1, y1, …), as a polygon.
List<double> _hull(List<double> p) {
  final n = p.length ~/ 2;
  final order = List.generate(n, (i) => i)
    ..sort((a, b) {
      final c = p[2 * a].compareTo(p[2 * b]);
      return c != 0 ? c : p[2 * a + 1].compareTo(p[2 * b + 1]);
    });
  double turn(int o, int a, int b) =>
      (p[2 * a] - p[2 * o]) * (p[2 * b + 1] - p[2 * o + 1]) -
      (p[2 * a + 1] - p[2 * o + 1]) * (p[2 * b] - p[2 * o]);
  final hull = <int>[];
  for (final pass in [order, order.reversed.toList()]) {
    final start = hull.length;
    for (final i in pass) {
      while (hull.length >= start + 2 && turn(hull[hull.length - 2], hull.last, i) <= 0) {
        hull.removeLast();
      }
      hull.add(i);
    }
    hull.removeLast();
  }
  return [
    for (final i in hull) ...[p[2 * i], p[2 * i + 1]],
  ];
}

/// The polygon (x0, y0, x1, y1, …) as a contour wound like the outlines'
/// (negative shoelace area, as a run's: left side forward, right side
/// back); nothing for one without area.
void _polygon(OutlineSink sink, List<double> p) {
  final n = p.length ~/ 2;
  if (n < 3) return;
  var area = 0.0;
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    area += p[2 * i] * p[2 * j + 1] - p[2 * j] * p[2 * i + 1];
  }
  if (area.abs() < 1e-12) return;
  final forward = area < 0;
  for (var k = 0; k < n; k++) {
    final i = forward ? k : n - 1 - k;
    if (k == 0) {
      sink.moveTo(p[2 * i], p[2 * i + 1]);
    } else {
      sink.lineTo(p[2 * i], p[2 * i + 1]);
    }
  }
  sink.close();
}
