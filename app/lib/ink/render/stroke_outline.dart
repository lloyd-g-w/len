import 'dart:math' as math;
import 'dart:ui';

import '../../domain/stroke.dart';
import '../input/point_spacing.dart';
import 'centerline.dart';
import 'outline_sink.dart';
import 'ribbon_emitter.dart';
import 'shape_params.dart';
import 'stroke_shaper.dart';

/// Shape parameters for [StrokeOutline.build].
class OutlineSpec {
  const OutlineSpec({
    required this.width,
    required this.thinning,
    required this.streamline,
    this.taperStart = 0,
    this.taperEnd = 0,
    this.flatCaps = false,
    this.unit = 0,
  });

  /// Nominal diameter at medium (0.5) pressure, in world units.
  final double width;

  /// How strongly pressure changes the width, 0..1.
  final double thinning;

  /// Stabiliser strength, 0..1: how much positional jitter is smoothed away.
  final double streamline;

  /// Lengths (world units) over which the ends taper to a point; 0 = none.
  final double taperStart;
  final double taperEnd;

  /// Square ends (highlighter) instead of round caps.
  final bool flatCaps;

  /// World units per screen pixel the stroke was written at
  /// (`StrokeStyle.unit`); 0: estimated from the points
  /// ([StrokeOutline.unitOf]).
  final double unit;

  /// Whether [other] draws the same outline for the same points.
  bool sameShape(OutlineSpec other) =>
      width == other.width &&
      thinning == other.thinning &&
      streamline == other.streamline &&
      taperStart == other.taperStart &&
      taperEnd == other.taperEnd &&
      flatCaps == other.flatCaps &&
      unit == other.unit;

  /// Outline radius at [pressure]: half the [width] at medium pressure,
  /// thinner/thicker with lighter/harder pressure as [thinning] allows.
  double radiusFor(double pressure) {
    final t = (0.5 - thinning * (0.5 - pressure)).clamp(0.0, 1.0);
    return (width * t).clamp(math.min(0.25, width / 2), width);
  }

  // The stabiliser ([streamline], 0..1) is the single control for all
  // smoothing (position smoothing: see [ShapeParams]).

  /// Length scale of the (causal) radius smoothing: from half a width at
  /// stabiliser 0 (just digitiser noise) to several widths.
  double get radiusSigma => width * (0.5 + 6 * streamline);

  /// Fastest allowed change of the radius per unit of length.
  double get maxRadiusSlope => 0.6 - 0.45 * streamline;

  /// Reach of the non-swelling start and end (world units).
  double get settleReach => math.min(width, 3.0);

  /// Reach of the levelled start and end (world units).
  double get levelReach => math.min(2 * width * streamline, width);

  /// The most the end rules may reach back from a moving pen tip: they
  /// change ink there as the pen moves on, so they stay within the tip.
  double get tipReach => 0.5 * width;

  /// The pipeline's numbers for this pen and a stroke written at [unit]
  /// world units per screen pixel ([StrokeOutline.unitOf]).
  ShapeParams paramsFor(double unit) => (_params[this] ??= {})[unit] ??= ShapeParams(
    width: width,
    unit: unit,
    streamline: streamline,
    radiusSigma: radiusSigma,
    maxRadiusSlope: maxRadiusSlope,
    settleReach: settleReach,
    levelReach: levelReach,
    tipReach: tipReach,
    taperStart: taperStart,
    taperEnd: taperEnd,
  );

  static final Expando<Map<double, ShapeParams>> _params = Expando('outline params');
}

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
  /// Builds the outline of [points]. [complete] is false while the stroke is still being drawn: the pen-up hook and the
  /// end taper are then left alone.
  static Path build(List<StrokePoint> points, OutlineSpec spec, {bool complete = true}) {
    final path = Path();
    emit(PathSink(path), points, spec, complete: complete);
    return path;
  }

  /// Like [build], but writes the outline's segments to [sink].
  static void emit(
    OutlineSink sink,
    List<StrokePoint> points,
    OutlineSpec spec, {
    bool complete = true,
  }) {
    final shaper = _shape(points, spec, complete);
    if (shaper.inputCount == 0) return;
    emitLine(sink, shaper, spec);
  }

  /// Emits the outline of an [update]d [shaper] (a dot when too short).
  static void emitLine(OutlineSink sink, StrokeShaper shaper, OutlineSpec spec) {
    if (isDot(shaper)) return dot(sink, shaper, spec);
    RibbonEmitter(
      shaper,
      flatCaps: spec.flatCaps,
      width: spec.width,
      step: shaper.p.step,
    ).emit(sink);
  }

  /// Whether the line is too short for anything but a dot.
  static bool isDot(StrokeShaper s) {
    if (s.length < 2) return true;
    if (s.p.step * (s.length - 1) >= s.p.width) return false; // radii ≤ width
    var maxR = 0.0;
    for (var i = 0; i < s.length; i++) {
      maxR = math.max(maxR, s.r[i]);
    }
    return s.p.step * (s.length - 1) < maxR * 0.5;
  }

  /// A dot for a (nearly) still contact: the largest input radius.
  static void dot(OutlineSink sink, StrokeShaper s, OutlineSpec spec) {
    final r = math.max(s.maxInputRadius, 0.25);
    final x = s.length > 0 ? s.x[0] : s.inputX(0), y = s.length > 0 ? s.y[0] : s.inputY(0);
    if (!spec.flatCaps) return addCircle(sink, x, y, r);
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
    return Centerline(s.x, s.y, s.r, shaper.p.step, corners: List.of(shaper.corners));
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

  static StrokeShaper _shape(List<StrokePoint> points, OutlineSpec spec, bool complete) {
    final shaper = feed(StrokeShaper(paramsOf(points, spec)), points, spec);
    if (complete) {
      shaper.update(ended: true, keep: shaper.endKeep());
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
