import 'dart:math' as math;
import 'dart:ui';

import 'wet_ink_segment.dart';

/// How far (px) the low-latency overlay's pieces [segments] reach outside
/// the ink [inside] says Flutter draws, and where: the shape jump seen
/// when the overlay lets go there (`FlickerLog.geometry`). (0, null) if
/// nowhere by more than [limit].
///
/// Cheap enough for every stroke while the flicker log records: each
/// piece's circles are probed in eight directions [limit] inside their
/// edge, and only probes Flutter's ink misses are followed further in.
/// Pieces at a flat end (butt caps, cut or swept: not their circles)
/// are skipped.
(double, Offset?) overlayExcess(
  List<WetSegment> segments,
  bool Function(Offset px) inside, {
  double limit = 0.5,
  double step = 0.25,
}) {
  var worst = 0.0;
  Offset? at;
  void probe(Offset c, double r) {
    for (var k = 0; k < 8; k++) {
      final u = Offset.fromDirection(k * math.pi / 4);
      var d = r - limit;
      if (d <= 0 || inside(c + u * d)) continue;
      while (d > 0 && !inside(c + u * d)) {
        d -= step;
      }
      final excess = r - math.max(0.0, d);
      if (excess > worst) {
        worst = excess;
        at = c + u * r;
      }
    }
  }

  for (final g in segments) {
    if (g.cuts.isNotEmpty || g.sweeps.isNotEmpty || g.flatA || g.flatB) continue;
    probe(g.a, g.ra);
    probe(g.b, g.rb);
  }
  return worst > limit ? (worst, at) : (0.0, null);
}
