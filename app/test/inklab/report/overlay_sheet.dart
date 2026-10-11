import 'dart:math' as math;
import 'dart:ui';

import 'package:len/ink/lab/replay_run.dart';

import '../metrics/outline_geometry.dart';
import '../metrics/overlay_metrics.dart';
import '../metrics/raster.dart';
import 'picture.dart';

/// Gap and ghost pixels (physical) of one overlay moment, as the
/// `overlay.*` metrics count them.
({List<Offset> gaps, List<Offset> ghosts}) _faults(OverlayMoment m) {
  final b = m.window;
  final f = Coverage.around(b)..fill(m.flutter);
  final o = Coverage.around(b)..fill(m.overlay);
  final ref = Coverage.around(b)..fill(m.reference);
  final gaps = <Offset>[], ghosts = <Offset>[];
  for (var y = b.top.floor(); y <= b.bottom.ceil(); y++) {
    for (var x = b.left.floor(); x <= b.right.ceil(); x++) {
      final cr = ref.at(x, y), cf = f.at(x, y), co = o.at(x, y);
      if (cr - math.max(cf, co) > 0.5) gaps.add(Offset(x.toDouble(), y.toDouble()));
      if (co - cr > 0.5) ghosts.add(Offset(x.toDouble(), y.toDouble()));
    }
  }
  return (gaps: gaps, ghosts: ghosts);
}

/// The low-latency overlay (wet ink) model against Flutter's ink, at the
/// [count] screen moments where they disagree most (in time order; the
/// first moments if they never do). Each tile, around the pen tip: light
/// grey = the ink Flutter will show once caught up, dark = what Flutter
/// shows now, translucent blue = the overlay's capsules, red = ghost ink
/// (overlay where no ink will be), orange = gap (ink missing from both).
Picture overlaySheet(ReplayResult r, {int count = 12, double tile = 200}) {
  final moments = overlayMoments(r);
  if (moments.isEmpty) return Picture(1, 1);
  final scored = [for (var i = 0; i < moments.length; i++) (i, _faults(moments[i]))];
  final ranked = [...scored]
    ..sort(
      (a, b) =>
          (b.$2.gaps.length + b.$2.ghosts.length).compareTo(a.$2.gaps.length + a.$2.ghosts.length),
    );
  final picked = ranked.take(count).toList()..sort((a, b) => a.$1.compareTo(b.$1));
  final tiles = <Picture>[];
  for (final (i, faults) in picked) {
    final m = moments[i];
    final scale = tile / math.max(m.window.width, m.window.height);
    final view = View.of(m.window, scale);
    final (w, h) = View.sizeOf(m.window, scale);
    List<Contour> map(List<Contour> cs) => [
      for (final c in cs) [for (final p in c) view(p)],
    ];
    final pic = Picture(w, h)
      ..fill(map(m.reference), Ink.inkLight)
      ..fill(map(m.flutter), Ink.ink)
      ..fill(map(m.overlay), Ink.overlay);
    void mark(List<Offset> pixels, int color) {
      for (final p in pixels) {
        final a = view(p), b = view(p + const Offset(1, 1));
        for (var y = a.dy.floor(); y < b.dy.ceil(); y++) {
          for (var x = a.dx.floor(); x < b.dx.ceil(); x++) {
            pic.blend(x, y, color, 0.8);
          }
        }
      }
    }

    mark(faults.ghosts, Ink.changed);
    mark(faults.gaps, Ink.gap);
    tiles.add(pic..frame(Ink.inkLight));
  }
  return sheet(tiles, columns: 4);
}
