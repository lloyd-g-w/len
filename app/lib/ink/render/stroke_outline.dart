import 'dart:math' as math;
import 'dart:ui';

import '../../domain/stroke.dart';
import '../input/point_spacing.dart';
import 'centerline.dart';
import 'outline_sink.dart';
import 'outline_spec.dart';
import 'ribbon_emitter.dart';
import 'shape_params.dart';
import 'stroke_shaper.dart';

export 'outline_spec.dart';

/// Builds filled outline paths for variable-width ink strokes.
///
/// [StrokeShaper] turns the points into a smoothed centre line with radii
/// (pen-down hook trimmed, resampled at a fixed step from the start,
/// finite low-pass smoothing between corners, causal radius smoothing,
/// end rules); [RibbonEmitter] outlines it with a few smooth contours.
/// Both have a fixed reach, so ink further than a few pen-widths behind
/// the tip of a stroke in progress never changes, and the committed
/// stroke equals the last live frame except at its very end.
abstract final class StrokeOutline {
  /// Builds the outline of [points]. [complete] is false while the stroke
  /// is still being drawn: the pen-up hook is then left alone.
  static Path build(List<StrokePoint> points, OutlineSpec spec, {bool complete = true}) {
    final path = Path();
    emit(PathSink(path), points, spec, complete: complete);
    return path;
  }

  /// Like [build], but writes the outline's segments to [sink]; sides fit
  /// within [tolerance] (world units) if given, else the screen's.
  static void emit(
    OutlineSink sink,
    List<StrokePoint> points,
    OutlineSpec spec, {
    bool complete = true,
    double? tolerance,
  }) {
    final shaper = _shape(points, spec, complete);
    if (shaper.inputCount == 0) return;
    emitLine(sink, shaper, spec, live: !complete, tolerance: tolerance);
  }

  /// Emits the outline of an [update]d [shaper] (a dot when too short);
  /// with [live], only what live ink shows ([StrokeShaper.liveLength], or
  /// the first [count] samples).
  static void emitLine(
    OutlineSink sink,
    StrokeShaper shaper,
    OutlineSpec spec, {
    bool live = false,
    int? count,
    double? tolerance,
  }) {
    if (isDot(shaper)) return dot(sink, shaper, spec);
    final full = live ? count ?? shaper.liveLength : shaper.length;
    final n = shownOf(full, shaper.length);
    if (n == 1) return _dotAt(sink, shaper.x[0], shaper.y[0], shaper.r[0], spec.flatCaps);
    RibbonEmitter(
      n < shaper.length ? RibbonPrefix(shaper, n) : shaper,
      flatCaps: spec.flatCaps,
      width: spec.width,
      step: shaper.p.step,
      tolerance: tolerance,
      lookahead: n < full && !spec.flatCaps ? 1 : 0,
    ).emit(sink);
  }

  /// The samples drawn of a line [length] samples long of which live ink
  /// may show [live] (`StrokeShaper.liveLength`): with the stabiliser on
  /// (fewer), one less, so the tangent where it ends is known (the next
  /// sample is final) and its end is drawn as the committed line has it
  /// there (`RibbonEmitter.lookahead`).
  static int shownOf(int live, int length) => live < length && live > 2 ? live - 1 : live;

  /// Whether the line is too short for anything but a dot.
  static bool isDot(StrokeShaper s) {
    if (s.length < 2) return true;
    if (s.p.step * (s.length - 1) >= s.p.width) return false; // radii ≤ width
    var maxR = 0.0;
    final r = s.untaperedR;
    for (var i = 0; i < s.length; i++) {
      maxR = math.max(maxR, r[i]);
    }
    return s.p.step * (s.length - 1) < maxR * 0.5;
  }

  /// A dot for a (nearly) still contact: the largest input radius.
  static void dot(OutlineSink sink, StrokeShaper s, OutlineSpec spec) {
    final r = math.max(s.maxInputRadius, 0.25);
    final x = s.length > 0 ? s.x[0] : s.inputX(0), y = s.length > 0 ? s.y[0] : s.inputY(0);
    _dotAt(sink, x, y, r, spec.flatCaps);
  }

  static void _dotAt(OutlineSink sink, double x, double y, double r, bool square) {
    if (!square) return addCircle(sink, x, y, r);
    sink
      ..moveTo(x - r, y - r)
      ..lineTo(x + r, y - r)
      ..lineTo(x + r, y + r)
      ..lineTo(x - r, y + r)
      ..close();
  }

  /// The smoothed centre line (with radii) [emit] outlines, or null for no
  /// points. For measurements (Ink Lab, tests).
  static Centerline? centerline(
    List<StrokePoint> points,
    OutlineSpec spec, {
    bool complete = true,
  }) {
    final shaper = _shape(points, spec, complete);
    if (shaper.length == 0) return null;
    final s = shaper.snapshot();
    return Centerline(
      s.x,
      s.y,
      s.r,
      shaper.p.step,
      corners: List.of(shaper.corners),
      live: shaper.liveLength,
    );
  }

  /// The index of the first point that is ink in a stroke of [points]
  /// (after the pen-down hook), deciding with whatever there is.
  static int startIndex(List<StrokePoint> points, OutlineSpec spec) {
    final shaper = _shape(points, spec, false);
    return shaper.started ? _pointIndex(points, shaper) : 0;
  }

  static int _pointIndex(List<StrokePoint> points, StrokeShaper shaper) {
    final x = shaper.inputX(shaper.startSample), y = shaper.inputY(shaper.startSample);
    for (var i = 0; i < points.length; i++) {
      if (points[i].x == x && points[i].y == y) return i;
    }
    return 0;
  }

  /// How many points [unitOf] looks at.
  static const int unitPoints = 9;

  /// The world size of a screen pixel when [points] were written: the
  /// spec's [OutlineSpec.unit] when the stroke recorded it (strokes drawn
  /// with the pen do), else estimated from the points' spacing: the input
  /// controller keeps points at least [PointSpacing.minDistance] screen px
  /// apart, and a pen usually lands slowly, so the closest spacings among
  /// the first [unitPoints] are about that distance (the second closest is
  /// used: a kept cusp tip may be closer; strokes too short to tell use 1).
  /// Clamped to a pen 1.5–40 screen px wide.
  ///
  /// Stroke data carry no zoom, but how smooth ink should be depends on it:
  /// the digitiser's jitter is a fraction of a *screen* pixel, so written
  /// zoomed in 7×, a pen's jitter is 7× smaller in world units.
  static double unitOf(List<StrokePoint> points, OutlineSpec spec) {
    final double u;
    if (spec.unit > 0) {
      u = spec.unit;
    } else {
      final n = math.min(points.length, unitPoints);
      final gaps = <double>[
        for (var i = 1; i < n; i++)
          if ((points[i].offset - points[i - 1].offset).distance case final d when d > 0) d,
      ]..sort();
      u = gaps.length < 2 ? 1.0 : gaps[1] / PointSpacing.minDistance;
    }
    return u.clamp(spec.width / 40, spec.width / 1.5);
  }

  /// The pipeline's numbers for [points] drawn with [spec].
  static ShapeParams paramsOf(List<StrokePoint> points, OutlineSpec spec) =>
      spec.paramsFor(unitOf(points, spec));

  /// The shaper of a complete stroke of [points], updated (its line, and
  /// where its samples fall: `StrokeShaper.phaseAt`).
  static StrokeShaper shaperOf(List<StrokePoint> points, OutlineSpec spec) =>
      _shape(points, spec, true);

  static StrokeShaper _shape(List<StrokePoint> points, OutlineSpec spec, bool complete) {
    final params = paramsOf(points, spec);
    final cutStart = spec.startPhase > 0;
    final shaper = feed(
      StrokeShaper(
        params,
        start: cutStart ? 0 : null,
        phase: cutStart ? spec.startPhase * params.step : null,
      ),
      points,
      spec,
    );
    if (complete) {
      shaper.taperEnd = spec.taperEnd;
      shaper.update(ended: true, keep: spec.cutEnd ? null : shaper.endKeep());
    } else {
      // Too short to decide its start: provisionally from the first point.
      shaper.update();
    }
    return shaper;
  }

  /// Adds [points] (from index [from]) to [shaper].
  static StrokeShaper feed(
    StrokeShaper shaper,
    List<StrokePoint> points,
    OutlineSpec spec, {
    int from = 0,
  }) {
    for (var i = from; i < points.length; i++) {
      final p = points[i];
      shaper.add(p.x, p.y, spec.radiusFor(p.pressure));
    }
    return shaper;
  }
}
