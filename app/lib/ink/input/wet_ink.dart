import 'dart:typed_data';

import '../../domain/stroke.dart';
import '../pen/pen_profile.dart';
import '../render/shape_params.dart';
import '../render/stroke_outline.dart';
import '../render/stroke_renderer.dart';
import 'live_ink.dart';
import 'point_spacing.dart';
import 'pressure_filter.dart';

/// How a platform overlay should draw the tip of the stroke being written
/// ("low-latency ink"): it paints the newest samples itself, before Flutter
/// can, until Flutter's own rendering of the live stroke catches up.
///
/// Only opaque, round, untextured ink qualifies — anywhere the overlay and
/// Flutter's ink overlap must look the same, which translucent or textured
/// ink would not.
class WetInkStyle {
  const WetInkStyle({
    required this.color,
    required this.radii,
    required this.shape,
    this.startUs = 0,
  });

  /// Opaque ARGB colour.
  final int color;

  /// Outline radius in logical screen pixels at pressures 0, 0.1, … 1
  /// ([steps] + 1 values); the overlay interpolates between them.
  final List<double> radii;

  /// The geometry rules the overlay applies (logical screen pixels), the
  /// same as Flutter's outline so both draw the same ink.
  final WetInkShape shape;

  /// Time (µs, event clock) of the first sample that is ink: samples
  /// before it are the pen-down hook, which Flutter trims.
  final int startUs;

  static const int steps = 10;

  /// The style of [live]'s stroke seen at viewport [scale], or null when it
  /// cannot be drawn faithfully by an overlay (or is not a free-hand stroke).
  static WetInkStyle? of(LiveInk live, double scale) {
    if (!live.isDrawing || live.straightened) return null;
    return forPen(
      live.tool,
      live.width,
      live.style,
      color: live.color,
      scale: scale,
      startUs: live.inkStartUs,
      unit: live.inkUnit,
    );
  }

  /// The style of ink drawn with [tool], [width] and [style] at viewport
  /// [scale], or null when an overlay cannot draw it faithfully.
  static WetInkStyle? forPen(
    InkTool tool,
    double width,
    StrokeStyle style, {
    required int color,
    required double scale,
    int startUs = 0,
    double unit = 1,
  }) {
    final profile = PenProfile.of(tool);
    final opaque = style.opacity >= 1 && (color >>> 24) == 0xFF;
    if (!opaque || profile.flatCaps || profile.textured || profile.nibVariation > 0) return null;
    final spec = StrokeRenderer.specFor(tool, width, style);
    return WetInkStyle(
      color: color,
      radii: [for (var i = 0; i <= steps; i++) spec.radiusFor(i / steps) * scale],
      shape: WetInkShape.of(spec, scale, unit),
      startUs: startUs,
    );
  }
}

/// The rules (beyond the radius table) that shape Flutter's ink near the pen
/// tip, for an overlay to follow: which samples become points, how the
/// pressure and radius are smoothed, the end rules and the pen-up hook. In
/// screen pixels (logical, or physical after [scaled]).
class WetInkShape {
  const WetInkShape({
    required this.minSpacing,
    required this.keepExtreme,
    required this.pressureKeep,
    required this.radiusSigma,
    required this.slope,
    required this.settleStart,
    required this.levelStart,
    required this.settleEnd,
    required this.levelEnd,
    required this.hookEnd,
    required this.hookBody,
    required this.hookLocal,
    required this.step,
    required this.dedupe,
    required this.kernel,
    required this.fit,
    required this.cornerK,
  });

  /// The rules of [spec] for a stroke of [unit] (`StrokeOutline.unitOf`)
  /// at viewport [scale] (world → logical px).
  factory WetInkShape.of(OutlineSpec spec, double scale, double unit) {
    final params = spec.paramsFor(unit);
    final hooks = params.hooks;
    return WetInkShape(
      minSpacing: PointSpacing.minDistance,
      keepExtreme: PointSpacing.keepExtreme,
      pressureKeep: PressureFilter.defaultSmoothing,
      radiusSigma: spec.radiusSigma * scale,
      slope: spec.maxRadiusSlope,
      settleStart: spec.settleReach * scale,
      levelStart: spec.levelReach * scale,
      settleEnd: (spec.settleReach < spec.tipReach ? spec.settleReach : spec.tipReach) * scale,
      levelEnd: (spec.levelReach < spec.tipReach ? spec.levelReach : spec.tipReach) * scale,
      hookEnd: hooks.maxEnd * scale,
      hookBody: hooks.body * scale,
      hookLocal: hooks.local * scale,
      step: params.step * scale,
      dedupe: params.dedupe * scale,
      kernel: params.kernel,
      fit: params.fit,
      cornerK: params.cornerK,
    );
  }

  /// Point thinning (see `PointSpacing`).
  final double minSpacing, keepExtreme;

  /// Weight the pressure filter keeps from the previous value.
  final double pressureKeep;

  /// Causal radius smoothing: length scale and steepest slope.
  final double radiusSigma, slope;

  /// Non-swelling / levelled reach at the start and at the tip.
  final double settleStart, levelStart, settleEnd, levelEnd;

  /// Pen-up hook rules (see `HookFinder`).
  final double hookEnd, hookBody, hookLocal;

  /// Position smoothing (see `StrokeShaper`): resampling step, merge
  /// distance, low-pass kernel (per sample), samples of the end fit, and
  /// the corner baseline in samples.
  final double step, dedupe;
  final List<double> kernel;
  final int fit, cornerK;

  /// The outline's position rules for points in these units.
  ShapeParams get positions => ShapeParams.positionsOf(
    ShapeParams.explicit(step: step, dedupe: dedupe, kernel: kernel, fit: fit, cornerK: cornerK),
    1,
  );

  /// The same rules with every length multiplied by [f] (e.g. the device
  /// pixel ratio).
  WetInkShape scaled(double f) => WetInkShape(
    minSpacing: minSpacing * f,
    keepExtreme: keepExtreme * f,
    pressureKeep: pressureKeep,
    radiusSigma: radiusSigma * f,
    slope: slope,
    settleStart: settleStart * f,
    levelStart: levelStart * f,
    settleEnd: settleEnd * f,
    levelEnd: levelEnd * f,
    hookEnd: hookEnd * f,
    hookBody: hookBody * f,
    hookLocal: hookLocal * f,
    step: step * f,
    dedupe: dedupe * f,
    kernel: kernel,
    fit: fit,
    cornerK: cornerK,
  );

  /// The values in the order the overlay's `begin` message carries them
  /// (the kernel last, it has as many values as are left).
  Float64List toList() => Float64List.fromList([
    minSpacing,
    keepExtreme,
    pressureKeep,
    radiusSigma,
    slope,
    settleStart,
    levelStart,
    settleEnd,
    levelEnd,
    hookEnd,
    hookBody,
    hookLocal,
    step,
    dedupe,
    fit.toDouble(),
    cornerK.toDouble(),
    ...kernel,
  ]);
}
