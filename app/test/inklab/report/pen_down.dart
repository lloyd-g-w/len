import 'dart:math' as math;
import 'dart:ui';

import 'package:len/domain/stroke.dart';
import 'package:len/ink/lab/replay_run.dart';

import '../metrics/contacts.dart';
import '../metrics/outline_geometry.dart';
import 'picture.dart';

/// Pen-down close-ups: for up to [contacts] contacts (bounces first, then
/// the ones whose start changed most, then evenly spread), one row of
/// [frames] tiles: the frame before pen-down, then each frame from the
/// first one built after it. Each tile is a [size] logical px window around
/// where the pen landed at [zoom]×: ink committed before (light grey), the
/// ink of the contact (grey; once committed black), the pen's raw samples handled so far (red
/// dots, the landing one ringed) and the pen's position (black ring).
/// Ink appearing at pen-down shows in the second tile under the ring.
Picture penDownStrip(
  ReplayResult r, {
  int contacts = 8,
  int frames = 8,
  double size = 28,
  double zoom = 8,
}) {
  final all = inkContacts(r.recording);
  if (all.isEmpty) return Picture(1, 1);
  final picks = <InkContact>{
    ...all.where((c) => c.bounce).take(2),
    for (var k = 0; k < contacts; k++)
      all[(k * (all.length - 1) / math.max(1, contacts - 1)).round()],
  }.take(contacts);
  final rows = <Picture>[];
  for (final c in picks) {
    final row = _row(r, c, frames, size, zoom);
    if (row != null) rows.add(row);
  }
  return sheet(rows, columns: 1);
}

Picture? _row(ReplayResult r, InkContact ink, int count, double size, double zoom) {
  final c = ink.contact;
  final landed = c.samples.first.position;
  final f0 = r.frames.indexWhere((f) => f.newestEventUs >= c.downUs);
  if (f0 < 0) return null;
  final area = Rect.fromCenter(center: landed, width: size, height: size);
  final view = View.of(area, zoom);
  final (w, h) = View.sizeOf(area, zoom);
  final tiles = <Picture>[];
  for (var k = math.max(0, f0 - 1); k < math.min(r.frames.length, f0 + count - 1); k++) {
    final f = r.frames[k];
    final pic = Picture(w, h);
    for (var j = 0; j <= k; j++) {
      for (final s in r.frames[j].committed) {
        final at = r.frames[j].toScreen;
        final own = (at(s.points.first.x, s.points.first.y) - landed).distance < 1;
        if (!own && !s.points.any((p) => (at(p.x, p.y) - landed).distance < size)) continue;
        final ink = _contours(r, r.frames[j], s.points, true, s.style, view);
        pic.fill(ink, own ? 0xFF000000 : Ink.inkLight);
      }
    }
    final mine =
        f.drawing && (f.toScreen(f.points.first.x, f.points.first.y) - landed).distance < 1;
    if (mine) {
      pic.fill(_contours(r, f, f.points, false, f.style, view), Ink.ink);
    }
    final seen = [
      for (final s in c.samples)
        if (s.timeUs <= f.newestEventUs) s,
    ];
    for (final s in seen) {
      pic.dot(view(s.position), 1.5, Ink.raw);
    }
    _ring(pic, view(landed), 3, Ink.raw);
    if (seen.isNotEmpty && f.newestEventUs <= c.upUs) {
      _ring(pic, view(seen.last.position), 6, 0xFF000000);
    }
    tiles.add(pic..frame(ink.bounce ? Ink.pop : (k < f0 ? Ink.inkLight : Ink.ink)));
  }
  return sheet(tiles, columns: tiles.length, gap: 3);
}

List<Contour> _contours(
  ReplayResult r,
  ReplayFrame f,
  List<StrokePoint> points,
  bool complete,
  StrokeStyle style,
  View view,
) => outlineOf(
  points,
  tool: r.pen.tool,
  width: r.pen.width,
  style: style,
  complete: complete,
  map: (o) => view(f.toScreen(o.dx, o.dy)),
  tolerance: 0.1,
).contours;

void _ring(Picture pic, Offset c, double radius, int color) {
  final ring = [for (var i = 0; i <= 24; i++) c + Offset.fromDirection(i * math.pi / 12, radius)];
  pic.line(ring, color);
}
