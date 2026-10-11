import 'dart:math' as math;
import 'dart:ui';

import '../../domain/stroke.dart';
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
    this.easing = _linear,
    this.taperStart = 0,
    this.taperEnd = 0,
    this.flatCaps = false,
  });

  /// Nominal diameter at medium (0.5) pressure, in world units.
  final double width;

  /// How strongly pressure changes the width, 0..1.
  final double thinning;

  /// Stabiliser strength, 0..1: how much positional jitter is smoothed away.
  final double streamline;

  /// Maps the pressure-derived size factor (0..1) to a radius factor.
  final double Function(double) easing;

  /// Lengths (world units) over which the ends taper to a point; 0 = none.
  final double taperStart;
  final double taperEnd;

  /// Square ends (highlighter) instead of round caps.
  final bool flatCaps;

  static double _linear(double t) => t;

  /// Whether [other] draws the same outline for the same points.
  bool sameShape(OutlineSpec other) =>
      width == other.width &&
      thinning == other.thinning &&
      streamline == other.streamline &&
      easing == other.easing &&
      taperStart == other.taperStart &&
      taperEnd == other.taperEnd &&
      flatCaps == other.flatCaps;

  /// Outline radius at [pressure]: half the [width] at medium pressure,
  /// thinner/thicker with lighter/harder pressure as [thinning] allows.
  double radiusFor(double pressure) {
    final t = (0.5 - thinning * (0.5 - pressure)).clamp(0.0, 1.0);
    return (width * easing(t)).clamp(math.min(0.25, width / 2), width);
  }

  // The stabiliser ([streamline], 0..1) is the single control for all
  // smoothing.

  /// Width-relative scale of the smoothing: small handwriting keeps its
  /// shape, wide pens get proportionally more.
  double get _scale => (width / 2.5).clamp(0.6, 1.6);

  /// Standard deviation (world units) of the positional smoothing. Never 0:
  /// at stabiliser 0 it removes the digitiser's sub-pixel jitter and keeps
  /// every visible detail (cusps are corners, which smoothing never
  /// crosses); it grows with the stabiliser.
  double get positionSigma => (0.55 + 1.2 * streamline) * _scale;

  /// Length scale of the (causal) radius smoothing: from half a width at
  /// stabiliser 0 (just digitiser noise) to several widths.
  double get radiusSigma => width * (0.5 + 6 * streamline);

  /// Fastest allowed change of the radius per unit of length.
  double get maxRadiusSlope => 0.6 - 0.45 * streamline;

  /// The pipeline's numbers for this pen.
  ShapeParams get params => _params[this] ??= ShapeParams(
    width: width,
    sigma: positionSigma,
    radiusSigma: radiusSigma,
    maxRadiusSlope: maxRadiusSlope,
    settleReach: math.min(width, 3.0),
    levelReach: math.min(2 * width * streamline, width),
    taperStart: taperStart,
    taperEnd: taperEnd,
  );

  static final Expando<ShapeParams> _params = Expando('outline params');

  /// Spacing of the resampled centre line.
  double get sampleStep => params.step;
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
  /// Builds the outline of [points]. [pressures], when given, overrides the
  /// per-point pressure (used for direction-dependent nibs). [complete] is
  /// false while the stroke is still being drawn: the pen-up hook and the
  /// end taper are then left alone.
  static Path build(
    List<StrokePoint> points,
    OutlineSpec spec, {
    List<double>? pressures,
    bool complete = true,
  }) {
    final path = Path();
    emit(PathSink(path), points, spec, pressures: pressures, complete: complete);
    return path;
  }

  /// Like [build], but writes the outline's segments to [sink].
  static void emit(
    OutlineSink sink,
    List<StrokePoint> points,
    OutlineSpec spec, {
    List<double>? pressures,
    bool complete = true,
  }) {
    final shaper = _shape(points, spec, pressures, complete);
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
    List<double>? pressures,
    bool complete = true,
  }) {
    final shaper = _shape(points, spec, pressures, complete);
    if (shaper.length == 0) return null;
    final s = shaper.snapshot();
    return Centerline(s.x, s.y, s.r, shaper.p.step, corners: List.of(shaper.corners));
  }

  /// Whether a live stroke of [points] may be shown: its start (pen-down
  /// hook, start rules) is decided and will not change any more.
  static bool startSettled(List<StrokePoint> points, OutlineSpec spec, {List<double>? pressures}) {
    final shaper = feed(StrokeShaper(spec.params), points, spec, pressures)..update();
    return shaper.startFinal;
  }

  static StrokeShaper _shape(
    List<StrokePoint> points,
    OutlineSpec spec,
    List<double>? pressures,
    bool complete,
  ) {
    final shaper = feed(StrokeShaper(spec.params), points, spec, pressures);
    if (complete) {
      shaper.update(ended: true, keep: shaper.endKeep());
    } else {
      shaper.update();
      // Too short to decide its start yet: shown as it is.
      if (!shaper.started) shaper.update(ended: true);
    }
    return shaper;
  }

  /// Adds [points] (from index [from]) to [shaper].
  static StrokeShaper feed(
    StrokeShaper shaper,
    List<StrokePoint> points,
    OutlineSpec spec,
    List<double>? pressures, {
    int from = 0,
  }) {
    for (var i = from; i < points.length; i++) {
      final p = points[i];
      shaper.add(p.x, p.y, spec.radiusFor(pressures?[i] ?? p.pressure));
    }
    return shaper;
  }
}
