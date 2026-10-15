import 'dart:math' as math;

import 'shape_params.dart';

/// Shape parameters for `StrokeOutline.build`.
class OutlineSpec {
  const OutlineSpec({
    required this.width,
    required this.thinning,
    required this.streamline,
    this.flatCaps = false,
    this.unit = 0,
    this.taperStart = 0,
    this.taperEnd = 0,
    this.startPhase = 0,
    this.cutEnd = false,
  });

  /// Nominal diameter at medium (0.5) pressure, in world units.
  final double width;

  /// How strongly pressure changes the width, 0..1.
  final double thinning;

  /// Stabiliser strength, 0..1: how much positional jitter is smoothed away.
  final double streamline;

  /// Butt caps, square to the stroke (the highlighter, flat pen ends),
  /// instead of round caps.
  final bool flatCaps;

  /// Lengths (world units) over which the start and the end narrow to a
  /// point (`Taper`); 0: that end has its cap. The end's applies only to a
  /// complete stroke (live ink cannot know where it will end).
  final double taperStart;
  final double taperEnd;

  /// A cut start's resampling phase, in steps (`StrokeStyle.startPhase`;
  /// 0: the pen's start), and whether the end is a cut
  /// (`StrokeStyle.cutEnd`). Cut ends keep their hooks.
  final double startPhase;
  final bool cutEnd;

  /// World units per screen pixel the stroke was written at
  /// (`StrokeStyle.unit`); 0: estimated from the points
  /// (`StrokeOutline.unitOf`).
  final double unit;

  /// Whether [other] draws the same outline for the same points.
  bool sameShape(OutlineSpec other) =>
      width == other.width &&
      thinning == other.thinning &&
      streamline == other.streamline &&
      flatCaps == other.flatCaps &&
      unit == other.unit &&
      taperStart == other.taperStart &&
      taperEnd == other.taperEnd &&
      startPhase == other.startPhase &&
      cutEnd == other.cutEnd;

  /// Whether [other] draws the same outline while the stroke is drawn:
  /// all but the end taper, which forms at pen-up.
  bool sameLiveShape(OutlineSpec other) => sameShape(other.withTaperEnd(taperEnd));

  /// A copy with the end taper [taperEnd].
  OutlineSpec withTaperEnd(double taperEnd) => taperEnd == this.taperEnd
      ? this
      : OutlineSpec(
          width: width,
          thinning: thinning,
          streamline: streamline,
          flatCaps: flatCaps,
          unit: unit,
          taperStart: taperStart,
          taperEnd: taperEnd,
          startPhase: startPhase,
          cutEnd: cutEnd,
        );

  /// Outline radius at [pressure]: half the [width] at medium pressure,
  /// thinner/thicker with lighter/harder pressure as [thinning] allows.
  double radiusFor(double pressure) {
    final t = (0.5 - thinning * (0.5 - pressure)).clamp(0.0, 1.0);
    return (width * t).clamp(math.min(0.25, width / 2), width);
  }

  /// The pressure [radiusFor] gives [radius] at (as near as 0..1 allows;
  /// any without [thinning]).
  double pressureFor(double radius) {
    if (thinning <= 0) return 0.5;
    return (0.5 - (0.5 - radius / width) / thinning).clamp(0.0, 1.0);
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
  /// world units per screen pixel (`StrokeOutline.unitOf`).
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
  );

  static final Expando<Map<double, ShapeParams>> _params = Expando('outline params');
}
