import 'dart:math' as math;
import 'dart:ui';

import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/wet_ink.dart';
import 'package:len/ink/lab/raw_samples.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/lab/wet_ink_model.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import 'metric.dart';
import 'outline_geometry.dart';
import 'raster.dart';
import 'temporal_metrics.dart';

/// A round-capped line from [a] to [b] with half width [r], as a polygon.
Contour capsulePolygon(Offset a, Offset b, double r, {int n = 16}) => hullPolygon(a, b, r, r, n: n);

/// The hull of the circles ([a], [ra]) and ([b], [rb]) as a polygon (a
/// capsule with unequal ends), as the overlay draws each piece.
Contour hullPolygon(Offset a, Offset b, double ra, double rb, {int n = 16}) {
  final d = b - a;
  final len = d.distance;
  if (len <= (ra - rb).abs()) {
    final (c, r) = ra >= rb ? (a, ra) : (b, rb);
    return [for (var i = 0; i < 4 * n; i++) c + Offset.fromDirection(math.pi * i / (2 * n), r)];
  }
  final angle = math.atan2(d.dy, d.dx);
  // The tangents touch at ±(π/2 + asin((rb − ra) / len)) from the direction.
  final t = math.pi / 2 + math.asin((rb - ra) / len);
  return [
    for (var i = 0; i <= n; i++) b + Offset.fromDirection(angle - t + 2 * t * i / n, rb),
    for (var i = 0; i <= n; i++)
      a + Offset.fromDirection(angle + t + (2 * math.pi - 2 * t) * i / n, ra),
  ];
}

/// The overlay's piece [g] as a polygon: [hullPolygon], or with its butt
/// caps (square to the piece; a dot with them is a square).
Contour segmentPolygon(WetSegment g, {int n = 16}) {
  if (!g.flatA && !g.flatB) return hullPolygon(g.a, g.b, g.ra, g.rb, n: n);
  final d = g.b - g.a;
  if (d.distance < 1e-9) {
    final r = g.ra;
    return [g.a + Offset(-r, -r), g.a + Offset(r, -r), g.a + Offset(r, r), g.a + Offset(-r, r)];
  }
  final angle = math.atan2(d.dy, d.dx);
  Iterable<Offset> end(Offset c, double r, double from, bool flat) => flat
      ? [c + Offset.fromDirection(from, r), c + Offset.fromDirection(from + math.pi, r)]
      : [for (var i = 0; i <= n; i++) c + Offset.fromDirection(from + math.pi * i / n, r)];
  return [
    ...end(g.b, g.rb, angle - math.pi / 2, g.flatB),
    ...end(g.a, g.ra, angle + math.pi / 2, g.flatA),
  ];
}

/// Median interval between consecutive frames (µs).
int frameIntervalUs(ReplayResult r) {
  final d = <int>[
    for (var i = 1; i < r.frames.length; i++)
      if (r.frames[i].vsyncUs > r.frames[i - 1].vsyncUs)
        r.frames[i].vsyncUs - r.frames[i - 1].vsyncUs,
  ]..sort();
  return d.isEmpty ? 16667 : d[d.length ~/ 2];
}

/// One moment on screen: Flutter's ink, the overlay's, and the ink
/// Flutter shows once it has caught up (the reference), physical px.
class OverlayMoment {
  OverlayMoment(this.flutter, this.overlay, this.reference, this.window);
  final List<Contour> flutter, overlay, reference;

  /// Where they can differ: around the overlay and the pen tip.
  final Rect window;
}

/// The screen moments of each contact with low-latency ink at Flutter
/// pipeline [depth] (frames from build to display).
List<OverlayMoment> overlayMoments(ReplayResult r, {int depth = 2}) =>
    overlayMomentsAt(r, depths: [depth])[depth]!;

/// [overlayMoments] for several pipeline [depths] in one pass (each frame's
/// outline is built once, and only a few are kept at a time; the moments
/// keep only the ink near the pen tip).
Map<int, List<OverlayMoment>> overlayMomentsAt(ReplayResult r, {required List<int> depths}) {
  final moments = {for (final d in depths) d: <OverlayMoment>[]};
  if (r.pen.tool.isHighlighter || r.style.opacity < 1) return moments;
  final dpr = r.recording.meta.devicePixelRatio;
  final frameUs = frameIntervalUs(r);
  final contacts = rawContacts(r.recording);
  List<(Rect, Contour)> ink(
    List<StrokePoint> p,
    bool complete,
    Offset Function(Offset) toPx,
    StrokeStyle style,
  ) => [
    for (final c in outlineOf(
      p,
      tool: r.pen.tool,
      width: r.pen.width,
      style: style,
      complete: complete,
      map: toPx,
    ).contours)
      (boundsOf([c]), c),
  ];

  for (final run in contactRuns(r)) {
    final stroke = run.committed;
    if (stroke == null) continue;
    // The screen as it was during this contact.
    final view = run.frames.first;
    final toPx = physical(r, view);
    final wet = WetInkStyle.forPen(
      r.pen.tool,
      r.pen.width,
      stroke.style,
      color: 0xFF000000,
      scale: view.viewScale,
    )!;
    final radii = [for (final x in wet.radii) x * dpr];
    final shape = wet.shape.scaled(dpr);
    // The end taper `end` carries (overlay px).
    final taperEnd =
        StrokeRenderer.specFor(r.pen.tool, r.pen.width, stroke.style).taperEnd *
        view.viewScale *
        dpr;
    final first = view.toScreen(run.frames.first.points.first.x, run.frames.first.points.first.y);
    final contact = contacts
        .where((c) => (c.samples.first.position - first).distance < 1)
        .firstOrNull;
    if (contact == null) continue;
    final models = {
      for (final d in depths) d: WetInkModel(radii: radii, shape: shape, frameMs: frameUs / 1000),
    };
    final delivered = {for (final d in depths) d: 0};
    final start = run.frames.first.index, end = run.frames.last.index;
    final outlines = <int, List<(Rect, Contour)>>{};
    List<(Rect, Contour)> shownAt(int k) => outlines[k] ??= k <= end
        ? ink(r.frames[k].points, false, toPx, stroke.style)
        : ink(stroke.points, true, toPx, stroke.style);
    // The committed stroke without its end taper: what the overlay stands
    // in for until Flutter has committed the stroke (the taper forms then,
    // measured by the end metrics).
    List<(Rect, Contour)>? untapered;
    List<(Rect, Contour)> referenceAt(int k, {required bool committed}) =>
        committed || k <= end || taperEnd <= 0
        ? shownAt(k)
        : untapered ??= ink(stroke.points, true, toPx, stroke.style.copyWith(taperEnd: 0));
    for (var k = start; k <= end + 2; k++) {
      outlines.remove(k - 1);
      for (final depth in depths) {
        if (k + depth >= r.frames.length) continue;
        final model = models[depth]!;
        // The progress Flutter reported two messages before the latest one
        // (frame k + depth − 1): before the first frame of the contact, it
        // has shown nothing of it.
        final shownIndex = math.min(k + depth - 1 - WetInkModel.progressLag, end);
        final shown = shownIndex < start ? contact.downUs : r.frames[shownIndex].newestEventUs;
        final ended = k + depth - 1 > end;
        final upTo = r.frames[k + depth].newestEventUs;
        var n = delivered[depth]!;
        while (n < contact.samples.length && contact.samples[n].timeUs <= upTo) {
          final s = contact.samples[n++];
          final lift = n == contact.samples.length;
          model.add(s.position * dpr, s.pressure, s.timeUs ~/ 1000, lift: lift);
        }
        delivered[depth] = n;
        if (model.samples.isEmpty) continue;
        if (ended) model.commit(taperEnd: taperEnd);
        // Frame k is on screen `depth` − 1 frame intervals after it was
        // built (in time: after a lift the app idles and the next recorded
        // frames come much later, but the commit frame is shown on time).
        final shownAtUs = math.min(
          r.frames[k + depth - 1].vsyncUs,
          r.frames[k].vsyncUs + (depth - 1) * frameUs,
        );
        final from = model.tailStart(
          nowMs: shownAtUs / 1000 + 1,
          shownUpToMs: shown / 1000,
          endedAtMs: ended ? r.frames[end + 1].vsyncUs / 1000 : null,
        );
        final overlay = from >= model.samples.length
            ? <Contour>[]
            : [for (final g in model.segments(from, model.samples.length)) segmentPolygon(g)];
        final tip = model.samples.last.position;
        final reach = radii.last * 2 + 2;
        var window = Rect.fromCircle(center: tip, radius: reach);
        if (overlay.isNotEmpty) window = window.expandToInclude(boundsOf(overlay).inflate(reach));
        moments[depth]!.add(
          OverlayMoment(
            _clip(shownAt(k), window),
            overlay,
            _clip(referenceAt(k + depth, committed: ended), window),
            window,
          ),
        );
      }
    }
  }
  return moments;
}

/// The parts of [ink] inside [window] (a little beyond it), each contour
/// clipped to it (Sutherland–Hodgman), so a moment keeps only what it is
/// judged on.
List<Contour> _clip(List<(Rect, Contour)> ink, Rect window) {
  final box = window.inflate(4);
  final out = <Contour>[];
  for (final (b, c) in ink) {
    if (!b.overlaps(box)) continue;
    if (box.contains(b.topLeft) && box.contains(b.bottomRight)) {
      out.add(c);
      continue;
    }
    var poly = c;
    for (final (inside, cross) in <(bool Function(Offset), Offset Function(Offset, Offset))>[
      ((p) => p.dx >= box.left, (a, b) => _atX(a, b, box.left)),
      ((p) => p.dx <= box.right, (a, b) => _atX(a, b, box.right)),
      ((p) => p.dy >= box.top, (a, b) => _atY(a, b, box.top)),
      ((p) => p.dy <= box.bottom, (a, b) => _atY(a, b, box.bottom)),
    ]) {
      if (poly.isEmpty) break;
      final next = <Offset>[];
      for (var i = 0; i < poly.length; i++) {
        final a = poly[(i + poly.length - 1) % poly.length], p = poly[i];
        if (inside(p)) {
          if (!inside(a)) next.add(cross(a, p));
          next.add(p);
        } else if (inside(a)) {
          next.add(cross(a, p));
        }
      }
      poly = next;
    }
    if (poly.length > 2) out.add(poly);
  }
  return out;
}

Offset _atX(Offset a, Offset b, double x) =>
    Offset(x, a.dy + (b.dy - a.dy) * (x - a.dx) / (b.dx - a.dx));
Offset _atY(Offset a, Offset b, double y) =>
    Offset(a.dx + (b.dx - a.dx) * (y - a.dy) / (b.dy - a.dy), y);

/// (h) Low-latency overlay: at every screen moment, Flutter's ink plus the
/// overlay's must cover what Flutter's ink will be once it catches up (no
/// gap), and the overlay must not draw where that ink is not (no ghost
/// ink, which shows as a bulge or a pop when the overlay retracts).
List<Metric> overlay(ReplayResult r) {
  final out = <Metric>[];
  final all = overlayMomentsAt(r, depths: const [2, 1, 3]);
  for (final depth in [2, 1, 3]) {
    final gap = Worst(), ghost = Worst();
    final dpr = r.recording.meta.devicePixelRatio;
    for (final m in all[depth]!) {
      final b = m.window;
      final f = Coverage.around(b)..fill(m.flutter);
      final o = Coverage.around(b)..fill(m.overlay);
      final ref = Coverage.around(b)..fill(m.reference);
      var gaps = 0, ghosts = 0;
      Offset? gapAt, ghostAt;
      for (var y = b.top.floor(); y <= b.bottom.ceil(); y++) {
        for (var x = b.left.floor(); x <= b.right.ceil(); x++) {
          final cr = ref.at(x, y), cf = f.at(x, y), co = o.at(x, y);
          if (cr - math.max(cf, co) > 0.5) {
            gaps++;
            gapAt ??= Offset(x / dpr, y / dpr);
          }
          if (co - cr > 0.5) {
            ghosts++;
            ghostAt ??= Offset(x / dpr, y / dpr);
          }
        }
      }
      gap.add(gaps.toDouble(), gapAt);
      ghost.add(ghosts.toDouble(), ghostAt);
    }
    final main = depth == 2;
    out
      ..add(
        Metric(
          'overlay.gap${main ? '' : '@$depth'}',
          gap.value,
          limit: main ? 0 : double.infinity,
          unit: ' px²',
          where: gap.where,
          note: 'Flutter shows frames $depth vsync(s) after building',
        ),
      )
      ..add(
        Metric(
          'overlay.ghost${main ? '' : '@$depth'}',
          ghost.value,
          limit: main ? 2 : double.infinity,
          unit: ' px²',
          where: ghost.where,
        ),
      );
  }
  return out;
}
