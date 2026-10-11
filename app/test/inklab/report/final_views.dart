import 'dart:math' as math;
import 'dart:ui';

import 'package:len/ink/lab/raw_samples.dart';

import '../metrics/edge_metrics.dart';
import '../metrics/evaluate.dart';
import '../metrics/metric.dart';
import '../metrics/outline_geometry.dart';
import '../metrics/raster.dart';
import 'picture.dart';

/// Metrics whose worst spot is the most telling place to zoom into, in
/// order of preference (a failing one wins over a passing one).
const List<String> _focusOrder = [
  'smooth.edgeBump16x',
  'smooth.facet',
  'ends.nub',
  'detail.retraction',
  'fidelity.hausdorff',
  'smooth.widthBump16x',
  'ends.blob',
];

/// Area (logical px) every truth path and committed stroke of [s] covers.
Rect inkBounds(Subject s, {double pad = 8}) {
  final r = s.replay;
  final points = [
    for (final t in s.truths) ...t.path,
    for (final st in r.strokes)
      for (final p in st.points) r.toScreen(p.x, p.y),
  ];
  if (points.isEmpty) return Rect.zero;
  return boundsOf([points]).inflate(pad);
}

/// Where to zoom in: the worst spot of the most telling metric, else the
/// middle of the first truth path.
Offset focusOf(Subject s, List<Metric> metrics) {
  Metric? pick(bool failing) {
    for (final id in _focusOrder) {
      final m = metrics.where((m) => m.id == id).firstOrNull;
      if (m != null && m.where != null && (!failing || !m.pass)) return m;
    }
    return null;
  }

  final m = pick(true) ?? pick(false);
  if (m != null) return m.where!;
  final path = s.truths.firstOrNull?.path ?? const [Offset.zero];
  return path[path.length ~/ 2];
}

/// The committed ink of [s] at [zoom] (× the device pixel ratio, so 1 is
/// what the screen shows) over [area], with the true path (green), the raw
/// digitiser samples (red) and the smoothed centre line (blue) on top.
Picture finalView(Subject s, Rect area, double zoom, {bool marks = true}) {
  final r = s.replay;
  final scale = zoom * r.recording.meta.devicePixelRatio;
  final view = View.of(area, scale);
  final (w, h) = View.sizeOf(area, scale);
  final pic = Picture(w, h);
  final contours = <Contour>[
    for (final st in r.strokes)
      ...outlineOf(
        st.points,
        tool: st.tool,
        width: st.width,
        style: st.style,
        complete: true,
        map: (o) => view(r.toScreen(o.dx, o.dy)),
        tolerance: 0.1,
      ).contours,
  ];
  pic.fill(contours, Ink.ink);
  if (!marks) return pic..frame(Ink.inkLight);
  final thin = math.max(1.0, scale / 8);
  for (final t in s.truths) {
    pic.line([for (final p in t.path) view(p)], Ink.truth, thickness: thin);
  }
  for (final line in committedLines(r)) {
    pic.line([for (final p in line.c) view(p)], Ink.centre, thickness: thin);
  }
  final dot = math.max(0.6, scale / 6);
  for (final c in rawContacts(r.recording)) {
    for (final sample in c.samples) {
      pic.dot(view(sample.position), dot, Ink.raw);
    }
  }
  pic.frame(Ink.inkLight);
  return pic;
}

/// The three final views of [s]: everything at 1× (plain, then marked), and
/// 4× and 16× around [focus]. Returns the pictures keyed by zoom.
Map<int, Picture> finalViews(Subject s, Offset focus) {
  final all = inkBounds(s);
  // Keep the 1× view to a sane size for long strokes.
  final whole = Rect.fromLTWH(
    all.left,
    all.top,
    math.min(all.width, 700),
    math.min(all.height, 400),
  );
  Rect around(double zoom) {
    final dpr = s.replay.recording.meta.devicePixelRatio;
    final w = 800 / (zoom * dpr), h = 500 / (zoom * dpr);
    return Rect.fromCenter(center: focus, width: w, height: h);
  }

  return {
    1: finalView(s, whole, 1),
    4: finalView(s, around(4), 4),
    16: finalView(s, around(16), 16),
  };
}
