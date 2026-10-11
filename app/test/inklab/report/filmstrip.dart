import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:len/domain/stroke.dart';
import 'package:len/ink/lab/replay_run.dart';

import '../metrics/outline_geometry.dart';
import '../metrics/raster.dart';
import '../metrics/temporal_metrics.dart';
import 'picture.dart';

/// Live frames of one contact rendered on a common grid, so consecutive
/// frames can be diffed pixel by pixel (the same rule as
/// `temporal.behindTip`: changes > 20 % outside the new samples, red when
/// more than a tip zone behind the tip, blue near it).
class _Frames {
  _Frames(this.r, this.run, this.area, this.scale)
    : view = View.of(area, scale),
      size = View.sizeOf(area, scale);

  final ReplayResult r;
  final ContactRun run;
  final Rect area;
  final double scale;
  final View view;
  final (int, int) size;

  Offset px(StrokePoint p) => view(run.frames.first.toScreen(p.x, p.y));

  Coverage coverage(List<StrokePoint> points, {required bool complete}) {
    final contours = outlineOf(
      points,
      tool: r.pen.tool,
      width: r.pen.width,
      style: r.style,
      complete: complete,
      map: (o) => view(run.frames.first.toScreen(o.dx, o.dy)),
      tolerance: 0.1,
    ).contours;
    return Coverage(0, 0, size.$1, size.$2)..fill(contours, subRows: 16);
  }

  double get zone => (r.pen.width * r.viewScale + 1) * scale;
  double get reach => (r.pen.width * r.viewScale + 1.5) * scale;

  /// Changed pixels from [a] (points [pa]) to [b] (points [pb]), split into
  /// behind the tip and near it.
  (List<Offset>, List<Offset>) diff(
    Coverage a,
    Coverage b,
    List<StrokePoint> pa,
    List<StrokePoint> pb, {
    double threshold = 0.2,
  }) {
    final tip = px(pa.last);
    final fresh = [for (final p in pb.skip(math.max(0, pa.length - 1))) px(p)];
    final changed = changedPixels(a, b, nearPolyline(fresh, reach), threshold);
    final behind = <Offset>[], near = <Offset>[];
    for (final p in changed) {
      ((p - tip).distance > zone ? behind : near).add(p);
    }
    return (behind, near);
  }
}

/// The contact of [r] drawn nearest [focus] (logical screen px), else the
/// longest; null if nothing was drawn live.
ContactRun? pickRun(ReplayResult r, Offset? focus) {
  final runs = contactRuns(r);
  if (runs.isEmpty) return null;
  if (focus != null) {
    double distance(ContactRun run) => run.frames.last.points
        .map((p) => (run.frames.first.toScreen(p.x, p.y) - focus).distance)
        .reduce(math.min);
    final near = runs.reduce((a, b) => distance(a) <= distance(b) ? a : b);
    if (distance(near) < 2 * r.pen.width * r.viewScale + 4) return near;
  }
  return runs.reduce((a, b) => a.frames.length >= b.frames.length ? a : b);
}

_Frames? _frames(
  ReplayResult r,
  Offset? focus, {
  required double maxWidth,
  required double maxScale,
}) {
  final run = pickRun(r, focus);
  if (run == null) return null;
  final points = [
    ...run.frames.last.points,
    ...?run.committed?.points,
  ].map((p) => run.frames.first.toScreen(p.x, p.y)).toList();
  final area = boundsOf([points]).inflate(r.pen.width * r.viewScale * 2 + 2);
  final scale = math.min(maxScale, maxWidth / math.max(area.width, 1));
  return _Frames(r, run, area, scale);
}

/// [count] live frames of one contact (the one at [focus], else the longest) — the [worst] whose ink
/// behind the tip changed most, the rest evenly spread — then the
/// committed stroke. Each tile shows what changed since the previous frame
/// (red: behind the tip, blue: at the tip; on the last tile, magenta: the
/// pop at pen-up). The tip is a small black ring.
Picture filmstrip(
  ReplayResult r,
  Offset? focus, {
  int count = 11,
  int worst = 4,
  int maxFrames = 400,
}) {
  final f = _frames(r, focus, maxWidth: 360, maxScale: 12);
  if (f == null) return Picture(1, 1);
  final frames = f.run.frames;
  final step = math.max(1, (frames.length / maxFrames).ceil());
  final behindCount = <int, int>{};
  for (var i = step; i < frames.length; i += step) {
    final a = f.coverage(frames[i - 1].points, complete: false);
    final b = f.coverage(frames[i].points, complete: false);
    behindCount[i] = f.diff(a, b, frames[i - 1].points, frames[i].points).$1.length;
  }
  final ranked = behindCount.keys.where((i) => behindCount[i]! > 0).toList()
    ..sort((a, b) => behindCount[b]!.compareTo(behindCount[a]!));
  final picks = <int>{...ranked.take(worst)};
  for (var k = 0; picks.length < count && k < count * 2; k++) {
    final i = ((frames.length - 1) * (k + 1) / count).round();
    if (i > 0 && i < frames.length) picks.add(i);
  }
  final tiles = <Picture>[];
  for (final i in picks.toList()..sort()) {
    final prev = frames[i - 1].points, cur = frames[i].points;
    final a = f.coverage(prev, complete: false), b = f.coverage(cur, complete: false);
    final pic = Picture(f.size.$1, f.size.$2)..paint(b, Ink.ink);
    final (behind, near) = f.diff(a, b, prev, cur);
    _mark(pic, near, Ink.nearTip);
    _mark(pic, behind, Ink.changed);
    _ring(pic, f.px(cur.last));
    tiles.add(pic..frame(behind.isEmpty ? Ink.inkLight : Ink.changed));
  }
  final committed = f.run.committed;
  if (committed != null) {
    final last = frames.last.points;
    final a = f.coverage(last, complete: false);
    final b = f.coverage(committed.points, complete: true);
    final pic = Picture(f.size.$1, f.size.$2)..paint(b, Ink.ink);
    final (behind, _) = f.diff(a, b, last, committed.points, threshold: 0.25);
    _mark(pic, behind, Ink.pop);
    tiles.add(pic..frame(Ink.pop));
  }
  return sheet(tiles, columns: 4);
}

/// Over every live frame of the contact at [focus] (else the longest): how often each pixel
/// changed behind the tip (yellow → red, more frames redder), drawn over
/// the committed ink (light grey); magenta: changed at pen-up.
Picture diffHeatmap(ReplayResult r, Offset? focus, {int maxFrames = 400}) {
  final f = _frames(r, focus, maxWidth: 900, maxScale: 8);
  if (f == null) return Picture(1, 1);
  final (w, h) = f.size;
  final counts = Int32List(w * h);
  final frames = f.run.frames;
  final step = math.max(1, (frames.length / maxFrames).ceil());
  Coverage? prev;
  List<StrokePoint>? prevPoints;
  for (var i = 0; i < frames.length; i += step) {
    final cov = f.coverage(frames[i].points, complete: false);
    if (prev != null) {
      final (behind, _) = f.diff(prev, cov, prevPoints!, frames[i].points);
      for (final p in behind) {
        counts[p.dy.floor() * w + p.dx.floor()]++;
      }
    }
    prev = cov;
    prevPoints = frames[i].points;
  }
  final pic = Picture(w, h);
  final committed = f.run.committed;
  if (committed != null) {
    pic.paint(f.coverage(committed.points, complete: true), Ink.inkLight);
  }
  final most = counts.fold(0, math.max);
  for (var i = 0; i < counts.length; i++) {
    if (counts[i] == 0) continue;
    final t = most <= 1 ? 1.0 : (counts[i] - 1) / (most - 1);
    pic.blend(i % w, i ~/ w, _heat(t), 1);
  }
  if (committed != null && prev != null) {
    final done = f.coverage(committed.points, complete: true);
    final (behind, _) = f.diff(prev, done, prevPoints!, committed.points, threshold: 0.25);
    _mark(pic, behind, Ink.pop);
  }
  return pic..frame(Ink.inkLight);
}

/// Yellow (t = 0) → red (t = 1).
int _heat(double t) => 0xFF000000 | (0xFF << 16) | ((0xD0 * (1 - t)).round() << 8);

void _mark(Picture pic, List<Offset> pixels, int color) {
  for (final p in pixels) {
    pic.blend(p.dx.floor(), p.dy.floor(), color, 0.85);
  }
}

void _ring(Picture pic, Offset c) {
  final ring = [for (var i = 0; i <= 16; i++) c + Offset.fromDirection(i * math.pi / 8, 4)];
  pic.line(ring, 0xFF000000);
}
