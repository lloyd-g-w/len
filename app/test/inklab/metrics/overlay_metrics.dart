import 'dart:math' as math;
import 'dart:ui';

import 'package:len/domain/stroke.dart';
import 'package:len/ink/lab/raw_samples.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/lab/wet_ink_model.dart';
import 'package:len/ink/pen/pen_profile.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import 'metric.dart';
import 'outline_geometry.dart';
import 'raster.dart';
import 'temporal_metrics.dart';

/// A round-capped line from [a] to [b] with half width [r], as a polygon.
Contour capsulePolygon(Offset a, Offset b, double r, {int n = 16}) {
  final d = b - a;
  final angle = d.distance == 0 ? 0.0 : math.atan2(d.dy, d.dx);
  return [
    for (var i = 0; i <= n; i++) b + Offset.fromDirection(angle - math.pi / 2 + math.pi * i / n, r),
    for (var i = 0; i <= n; i++) a + Offset.fromDirection(angle + math.pi / 2 + math.pi * i / n, r),
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
///
/// [cache] keeps flattened outlines per frame between calls.
List<OverlayMoment> overlayMoments(
  ReplayResult r, {
  int depth = 2,
  Map<(int, int), List<(Rect, Contour)>>? cache,
}) {
  final outlines = cache ?? {};
  final profile = PenProfile.of(r.pen.tool);
  if (profile.flatCaps || profile.textured || profile.nibVariation > 0 || r.style.opacity < 1) {
    return const [];
  }
  final dpr = r.recording.meta.devicePixelRatio;
  final toPx = physical(r);
  final frameUs = frameIntervalUs(r);
  final radii = [
    for (var i = 0; i <= 10; i++)
      StrokeRenderer.radiusAt(profile, r.pen.width, r.style, i / 10) * r.viewScale * dpr,
  ];
  final contacts = rawContacts(r.recording);
  final moments = <OverlayMoment>[];
  List<(Rect, Contour)> ink(List<StrokePoint> p, bool complete) => [
    for (final c in outlineOf(
      p,
      tool: r.pen.tool,
      width: r.pen.width,
      style: r.style,
      complete: complete,
      map: toPx,
    ).contours)
      (boundsOf([c]), c),
  ];

  for (final run in contactRuns(r)) {
    final stroke = run.committed;
    if (stroke == null) continue;
    final first = r.toScreen(run.frames.first.points.first.x, run.frames.first.points.first.y);
    final contact = contacts
        .where((c) => (c.samples.first.position - first).distance < 1)
        .firstOrNull;
    if (contact == null) continue;
    final model = WetInkModel(radii: radii, frameMs: frameUs / 1000);
    var delivered = 0;
    final start = run.frames.first.index, end = run.frames.last.index;
    List<(Rect, Contour)> shownAt(int k) => outlines[(start, k)] ??= k <= end
        ? ink(r.frames[k].points, false)
        : ink(stroke.points, true);
    List<Contour> clip(List<(Rect, Contour)> ink, Rect window) => [
      for (final (b, c) in ink)
        if (b.overlaps(window)) c,
    ];
    for (var k = start; k <= end + 2 && k + depth < r.frames.length; k++) {
      final progress = r.frames[math.min(k + depth - 1, end)].newestEventUs;
      final ended = k + depth - 1 > end;
      final upTo = r.frames[k + depth].newestEventUs;
      while (delivered < contact.samples.length && contact.samples[delivered].timeUs <= upTo) {
        final s = contact.samples[delivered++];
        model.add(s.position * dpr, s.pressure, s.timeUs ~/ 1000);
      }
      if (delivered == 0) continue;
      final from = model.tailStart(
        nowMs: r.frames[k + depth - 1].vsyncUs / 1000 + 1,
        flutterUpToMs: progress / 1000,
        endedAtMs: ended ? r.frames[end + 1].vsyncUs / 1000 : null,
      );
      final overlay = from >= model.samples.length
          ? <Contour>[]
          : [
              for (final (a, b, w) in model.segments(from, model.samples.length))
                capsulePolygon(a, b, w),
            ];
      final tip = model.samples.last.position;
      final reach = radii.last * 2 + 2;
      var window = Rect.fromCircle(center: tip, radius: reach);
      if (overlay.isNotEmpty) window = window.expandToInclude(boundsOf(overlay).inflate(reach));
      moments.add(
        OverlayMoment(clip(shownAt(k), window), overlay, clip(shownAt(k + depth), window), window),
      );
    }
  }
  return moments;
}

/// (h) Low-latency overlay: at every screen moment, Flutter's ink plus the
/// overlay's must cover what Flutter's ink will be once it catches up (no
/// gap), and the overlay must not draw where that ink is not (no ghost
/// ink, which shows as a bulge or a pop when the overlay retracts).
List<Metric> overlay(ReplayResult r) {
  final out = <Metric>[];
  final cache = <(int, int), List<(Rect, Contour)>>{};
  for (final depth in [2, 1, 3]) {
    final gap = Worst(), ghost = Worst();
    final dpr = r.recording.meta.devicePixelRatio;
    for (final m in overlayMoments(r, depth: depth, cache: cache)) {
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
