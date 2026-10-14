import 'dart:math' as math;
import 'dart:ui';

import 'package:len/domain/stroke.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import 'contacts.dart';
import 'metric.dart';
import 'outline_geometry.dart';
import 'overlay_metrics.dart' show frameIntervalUs;
import 'raster.dart';

/// The live frames of one contact and the stroke it committed (if any).
class ContactRun {
  ContactRun(this.frames, this.committed);
  final List<ReplayFrame> frames;
  final Stroke? committed;
}

/// Splits a replay into contacts: runs of drawing frames sharing a first
/// point, each with the stroke committed right after it.
List<ContactRun> contactRuns(ReplayResult replay) {
  final runs = <ContactRun>[];
  var current = <ReplayFrame>[];
  void close(ReplayFrame? after) {
    if (current.isEmpty) return;
    runs.add(ContactRun(current, after?.committed.firstOrNull));
    current = [];
  }

  for (final f in replay.frames) {
    final same =
        current.isNotEmpty &&
        f.drawing &&
        f.points.first.x == current.first.points.first.x &&
        f.points.first.y == current.first.points.first.y;
    if (f.drawing && (current.isEmpty || same)) {
      current.add(f);
    } else {
      close(f);
      if (f.drawing) current.add(f);
    }
  }
  close(null);
  return runs;
}

/// Sub-scanlines per pixel for the frame diffs. With 5, a near-horizontal
/// edge moving by a hundredth of a pixel across a sub-scanline flips a
/// whole 0.2 of coverage, exactly the 20 % threshold (see INK_LAB.md,
/// "Metric fixes"); 16 resolves coverage to 1/16.
const int _subRows = 16;

/// Maps world points to physical pixels of the replayed screen (as it was
/// at [frame], default: as it ended up).
Offset Function(Offset) physical(ReplayResult r, [ReplayFrame? frame]) {
  final dpr = r.recording.meta.devicePixelRatio;
  final toScreen = frame?.toScreen ?? r.toScreen;
  return (o) => toScreen(o.dx, o.dy) * dpr;
}

List<Contour> _outline(
  ReplayResult r,
  List<StrokePoint> points,
  Offset Function(Offset) map, {
  required bool complete,
  required StrokeStyle style,
}) => outlineOf(
  points,
  tool: r.pen.tool,
  width: r.pen.width,
  style: style,
  complete: complete,
  map: map,
).contours;

/// Pixels (physical) whose coverage changes by more than [threshold]
/// between [a] and [b], outside [allowed].
List<Offset> changedPixels(
  Coverage a,
  Coverage b,
  bool Function(Offset) allowed,
  double threshold,
) {
  final out = <Offset>[];
  final l = math.min(a.left, b.left), t = math.min(a.top, b.top);
  final r = math.max(a.left + a.width, b.left + b.width);
  final btm = math.max(a.top + a.height, b.top + b.height);
  for (var y = t; y < btm; y++) {
    for (var x = l; x < r; x++) {
      if ((a.at(x, y) - b.at(x, y)).abs() <= threshold) continue;
      final p = Offset(x + 0.5, y + 0.5);
      if (!allowed(p)) out.add(p);
    }
  }
  return out;
}

/// True within [radius] of the polyline through [points].
bool Function(Offset) nearPolyline(List<Offset> points, double radius) => (p) {
  for (var i = 0; i < points.length; i++) {
    if ((points[i] - p).distance <= radius) return true;
    if (i > 0 && _segDist(p, points[i - 1], points[i]) <= radius) return true;
  }
  return false;
};

double _segDist(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (l2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// The part of the line of [points] live ink shows (screen px), with the
/// stabiliser on all of it final (`StrokeShaper.liveLength`).
List<Offset>? _drawn(List<StrokePoint> points, OutlineSpec spec, Offset Function(Offset) toPx) {
  final c = StrokeOutline.centerline(points, spec, complete: false);
  if (c == null) return null;
  return [for (var i = 0; i < c.live; i++) toPx(Offset(c.x[i], c.y[i]))];
}

/// The rest of that line: what live ink does not show yet.
List<Offset>? _undrawn(List<StrokePoint> points, OutlineSpec spec, Offset Function(Offset) toPx) {
  final c = StrokeOutline.centerline(points, spec, complete: false);
  if (c == null) return null;
  return [for (var i = math.max(0, c.live - 1); i < c.length; i++) toPx(Offset(c.x[i], c.y[i]))];
}

/// (d) Temporal stability: between consecutive live frames, ink more than
/// a tip zone (one stroke width + 1 px) behind the pen tip must not change.
/// Reports changed pixels (> 20 % coverage) outside the zone and new
/// segment, and how far behind the tip changes reach. Also (e) the pop at
/// pen-up: the last live frame against the committed stroke, outside the
/// samples that arrived after that frame.
///
/// One change is allowed behind the tip: ink shows from pen-down, before
/// the pen-down hook is decided ([HookFinder], within the first few px), so
/// once per contact, in the frame where the stroke's start moves past a
/// trimmed hook, the ink of the hook (within [reach] of its points, at most
/// `HookFinder.maxStart` long) may go. A second start change is not exempt.
///
/// Bounces (see [inkContacts]) show while they touch and are not committed:
/// `temporal.vanished` counts only intended contacts that vanish, and
/// `temporal.bounceFlash` how long a bounce shows.
List<Metric> temporal(ReplayResult r, {int maxFramesPerRun = 400}) {
  final dpr = r.recording.meta.devicePixelRatio;
  final behind = Worst(), settle = Worst(), pop = Worst(), popMax = Worst();
  final flash = Worst();
  var vanished = 0;
  final contacts = inkContacts(r.recording);
  final frameMs = frameIntervalUs(r) / 1000;
  var zone = (r.pen.width * r.viewScale + 1) * dpr;
  for (final run in contactRuns(r)) {
    final frames = run.frames;
    // The screen as it was during this contact.
    final view = frames.first;
    final toPx = physical(r, view);
    zone = (r.pen.width * view.viewScale + 1) * dpr;
    final reach = r.pen.width * view.viewScale * dpr + 1.5 * dpr; // around new samples
    final step = math.max(1, (frames.length / maxFramesPerRun).ceil());
    final spec = StrokeRenderer.specFor(r.pen.width, view.style);
    var startMoved = false;
    final lags = spec.paramsFor(StrokeOutline.unitOf(view.points, spec)).lag > 0;
    List<Offset>? prevLine;
    Coverage? prev;
    List<StrokePoint>? prevPoints;
    for (var i = 0; i < frames.length; i += step) {
      final points = frames[i].points;
      final contours = _outline(r, points, toPx, complete: false, style: view.style);
      final cov = rasterize(contours, boundsOf(contours), subRows: _subRows);
      final drawn = lags ? _drawn(points, spec, toPx) : null;
      if (prev != null && prevPoints != null) {
        // With the stabiliser on, live ink ends behind the pen: its tip is
        // where the drawn line ends, and what is new is the line drawn since.
        final prevDrawn = prevLine;
        final tip = prevDrawn != null && prevDrawn.isNotEmpty
            ? prevDrawn.last
            : toPx(Offset(prevPoints.last.x, prevPoints.last.y));
        final fresh = prevDrawn != null && drawn != null
            ? drawn.skip(math.max(0, prevDrawn.length - 1)).toList()
            : [for (final p in points.skip(prevPoints.length - 1)) toPx(Offset(p.x, p.y))];
        var allowed = nearPolyline(fresh, reach);
        // The pen-down hook trimmed (decided within the first few px).
        if (!startMoved && _screenLength(prevPoints, view.viewScale) < 20) {
          final was = StrokeOutline.startIndex(prevPoints, spec);
          final now = StrokeOutline.startIndex(points, spec);
          if (now != was) {
            startMoved = true;
            final hook = [for (final p in points.take(now + 1)) toPx(Offset(p.x, p.y))];
            final isNew = allowed, inHook = nearPolyline(hook, reach);
            allowed = (p) => isNew(p) || inHook(p);
          }
        }
        final changed = changedPixels(prev, cov, allowed, 0.2);
        final outside = changed.where((p) => (p - tip).distance > zone).toList();
        behind.add(outside.length.toDouble(), outside.isEmpty ? null : outside.first / dpr);
        for (final p in changed) {
          settle.add((p - tip).distance / dpr, p / dpr);
        }
      }
      prev = cov;
      prevPoints = points;
      prevLine = drawn;
    }
    final stroke = run.committed;
    if (stroke == null) {
      final first = view.toScreen(view.points.first.x, view.points.first.y);
      final bounce = contacts
          .where((c) => (c.contact.samples.first.position - first).distance < 1)
          .firstOrNull
          ?.bounce;
      if (bounce ?? false) {
        flash.add(frames.length * frameMs, first);
      } else {
        vanished++;
      }
      continue;
    }
    final last = frames.last.points;
    final done = _outline(r, stroke.points, toPx, complete: true, style: stroke.style);
    final liveOutline = _outline(r, last, toPx, complete: false, style: view.style);
    final a = rasterize(liveOutline, boundsOf(liveOutline), subRows: _subRows);
    final b = rasterize(done, boundsOf(done), subRows: _subRows);
    final tail = [
      // With the stabiliser on, the line live ink did not show yet.
      if (lags) ...?_undrawn(last, spec, toPx),
      for (final p in stroke.points.skip(math.max(0, last.length - 1))) toPx(Offset(p.x, p.y)),
    ];
    final changed = changedPixels(a, b, nearPolyline(tail, reach), 0.25);
    pop.add(changed.length.toDouble(), changed.isEmpty ? null : changed.first / dpr);
    for (final p in changed) {
      popMax.add(
        (a.at(p.dx.floor(), p.dy.floor()) - b.at(p.dx.floor(), p.dy.floor())).abs(),
        p / dpr,
      );
    }
  }
  return [
    Metric(
      'temporal.behindTip',
      behind.value,
      limit: 0,
      unit: ' px²',
      where: behind.where,
      note:
          'physical pixels changing > 20 % more than ${(zone / dpr).toStringAsFixed(1)} px behind the tip',
    ),
    Metric(
      'temporal.settle',
      settle.value,
      limit: zone / dpr,
      unit: 'px',
      where: settle.where,
      note: 'farthest change from the previous tip',
    ),
    Metric(
      'pop.pixels',
      pop.value,
      limit: 2,
      unit: ' px²',
      where: pop.where,
      note: 'physical pixels changing > 25 % at pen-up (outside the final samples)',
    ),
    Metric('pop.max', popMax.value * 100, limit: 50, unit: '%', where: popMax.where),
    Metric(
      'temporal.vanished',
      vanished.toDouble(),
      limit: 0,
      note: 'intended contacts drawn live but never committed',
    ),
    Metric(
      'temporal.bounceFlash',
      flash.value,
      limit: 100,
      unit: ' ms',
      where: flash.where,
      note: 'how long a bounce shows (it touches < 80 ms; plus the frame of its lift)',
    ),
  ];
}

/// Length of the polyline through [points] on screen (logical px).
double _screenLength(List<StrokePoint> points, double scale) {
  var d = 0.0;
  for (var i = 1; i < points.length; i++) {
    d += (points[i].offset - points[i - 1].offset).distance;
  }
  return d * scale;
}
