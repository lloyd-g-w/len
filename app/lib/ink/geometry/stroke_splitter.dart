import 'dart:math' as math;
import 'dart:ui';

import '../../domain/stroke.dart';
import '../render/stroke_outline.dart';
import '../render/stroke_renderer.dart';
import '../render/stroke_shaper.dart';
import '../stroke_hit_test.dart';

/// Geometry of the pixel (partial) eraser: cuts the part of a stroke under
/// the eraser out and keeps what survives as new strokes.
///
/// The rest of the ink stays where it was: a fragment's centre line is
/// resampled with the original's phase (`StrokeStyle.startPhase`), so its
/// samples fall where the original's did and the shaper's rules (corners,
/// smoothing) decide as they did beyond their short reach from the cut.
/// Cut ends keep their hooks (`StrokeStyle.cutEnd`).
abstract final class StrokeSplitter {
  /// Caps the points inserted into one segment (very long straight lines).
  static const int _maxInserted = 1024;

  /// Erases the part of [stroke] within [radius] of the segment [a]→[b].
  ///
  /// Returns null when nothing is erased, otherwise the surviving fragments
  /// (possibly none), each a new stroke with an id from [newId]. Fragments
  /// keep the original's creation time and style, so they paint in the
  /// same order and look; only the outline is cut (a filled shape's
  /// fragments are open and have no fill).
  static List<Stroke>? erase(
    Stroke stroke,
    Offset a,
    Offset b,
    double radius, {
    required String Function() newId,
  }) {
    if (!StrokeHitTest.sweepHits(stroke, a, b, radius, fill: false)) return null;
    // Points are cut where the eraser touches the ink's edge (which depends
    // on the pressure there), so fragment end caps line up with the eraser
    // circle.
    bool erased(StrokePoint p) {
      final reach = radius + StrokeHitTest.inkRadius(stroke, p);
      return StrokeHitTest.segmentDistSq(p.offset, p.offset, a, b) <= reach * reach;
    }

    if (stroke.points.length == 1) return erased(stroke.points.single) ? const [] : null;

    // The ink is never wider than the nominal width on either side.
    final maxReach = radius + stroke.width;
    final source = <int>[];
    final points = _densify(
      stroke.points,
      a,
      b,
      maxReach * maxReach,
      step: math.max(radius / 3, 0.2),
      source: source,
    );
    final keep = [for (final p in points) !erased(p)];
    if (!keep.contains(false)) return null;

    // Fragments keep the scale the original was shaped at (estimated from
    // its first points when not recorded).
    final spec = StrokeRenderer.specFor(stroke.tool, stroke.width, stroke.style);
    // Fragments are open, so a filled shape's pieces have no fill.
    final style = stroke.style.withFill(null);
    final base = style.unit > 0
        ? style
        : style.copyWith(unit: StrokeOutline.unitOf(stroke.points, spec));
    StrokeShaper? shaped;

    final fragments = <Stroke>[];
    var start = -1;
    for (var i = 0; i <= points.length; i++) {
      final kept = i < points.length && keep[i];
      if (kept && start < 0) start = i;
      if (!kept && start >= 0) {
        if (i - start >= 2) {
          final cutStart = start > 0, cutEnd = i < points.length;
          // A taper only stays at an end of the original stroke (a cut
          // end is a cap).
          var style = base.copyWith(
            taperStart: cutStart ? 0 : null,
            taperEnd: cutEnd ? 0 : null,
            cutEnd: cutEnd ? true : null,
          );
          final part = points.sublist(start, i);
          if (cutStart) {
            shaped ??= StrokeOutline.shaperOf(stroke.points, spec);
            part[0] = _settledStart(shaped, spec, points, source, start);
            final phase = _phase(shaped, stroke, part, source.sublist(start, i), style);
            style = style.copyWith(startPhase: phase);
          }
          fragments.add(stroke.withPoints(part, id: newId(), style: style));
        }
        start = -1;
      }
    }
    return fragments;
  }

  /// The resampling phase (in steps, 0 < phase ≤ 1) for a fragment of
  /// [points] with [style], cut from [original] (shaped by [shaper]), that
  /// puts its samples where the original's are. [source] gives each
  /// point's index in the original (−1: inserted at the cut).
  ///
  /// From the first point whose neighbour before is an original point too,
  /// both lines run through the same points with the same neighbours, so
  /// their resampling splines are the same; there the phases must match.
  static double _phase(
    StrokeShaper shaper,
    Stroke original,
    List<StrokePoint> points,
    List<int> source,
    StrokeStyle style,
  ) {
    // A first guess, then shifted by the difference where the lines meet.
    final spec = StrokeRenderer.specFor(
      original.tool,
      original.width,
      style.copyWith(startPhase: 1),
    );
    final fragment = StrokeOutline.shaperOf(points, spec);
    final step = fragment.p.step;
    for (var m = 1; m < points.length; m++) {
      if (source[m - 1] < 0 || source[m] < 0) continue;
      final sample = fragment.sampleStartingAt(m);
      final originalSample = shaper.sampleStartingAt(source[m]);
      if (sample == null || originalSample == null) continue;
      // Within a trimmed pen-down hook the original has no samples yet.
      if (originalSample < shaper.startSample) continue;
      final want = shaper.phaseAt(originalSample), got = fragment.phaseAt(sample);
      if (want == null || got == null) break;
      final phase = (step + want - got) % step;
      return phase <= step * 1e-9 ? 1 : phase / step;
    }
    return 1;
  }

  /// The cut point [points]`[at]` with the pressure that gives the
  /// original's ink radius there ([shaper]'s smoothed radius at its
  /// nearest sample on that input segment). The fragment's radius
  /// smoothing starts from it, so its width does not swing towards the raw
  /// pressure at the cut and back.
  static StrokePoint _settledStart(
    StrokeShaper shaper,
    OutlineSpec spec,
    List<StrokePoint> points,
    List<int> source,
    int at,
  ) {
    final q = points[at];
    if (spec.thinning <= 0) return q;
    // The original's input points before and after the cut point.
    var before = at, after = at;
    while (source[before] < 0) {
      before--;
    }
    while (source[after] < 0) {
      after++;
    }
    final from = shaper.firstSampleOf(shaper.sampleOfPoint(source[before]));
    final to = shaper.firstSampleOf(shaper.sampleOfPoint(source[after]));
    if (from == null || to == null) return q;
    final r = shaper.untaperedR;
    var nearest = -1, best = double.infinity;
    for (var k = math.max(0, from - 1); k <= math.min(to, shaper.length - 1); k++) {
      final dx = shaper.x[k] - q.x, dy = shaper.y[k] - q.y;
      if (dx * dx + dy * dy < best) {
        best = dx * dx + dy * dy;
        nearest = k;
      }
    }
    if (nearest < 0) return q;
    return StrokePoint(q.x, q.y, spec.pressureFor(r[nearest]));
  }

  /// Inserts interpolated points (every [step] units) into the segments
  /// that pass within reach of the eraser, so the cut follows the eraser
  /// closely even where the input was sampled sparsely. [source] receives
  /// each output point's index in [points] (−1 for inserted ones).
  static List<StrokePoint> _densify(
    List<StrokePoint> points,
    Offset a,
    Offset b,
    double reachSq, {
    required double step,
    required List<int> source,
  }) {
    final out = <StrokePoint>[points.first];
    source.add(0);
    for (var i = 1; i < points.length; i++) {
      final p0 = points[i - 1], p1 = points[i];
      final length = (p1.offset - p0.offset).distance;
      final near = StrokeHitTest.segmentDistSq(p0.offset, p1.offset, a, b) <= reachSq;
      if (near && length > step) {
        final n = math.min((length / step).ceil(), _maxInserted);
        for (var k = 1; k < n; k++) {
          final t = k / n;
          out.add(
            StrokePoint(
              p0.x + (p1.x - p0.x) * t,
              p0.y + (p1.y - p0.y) * t,
              p0.pressure + (p1.pressure - p0.pressure) * t,
            ),
          );
          source.add(-1);
        }
      }
      out.add(p1);
      source.add(i);
    }
    return out;
  }
}
