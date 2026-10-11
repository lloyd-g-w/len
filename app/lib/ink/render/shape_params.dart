import 'dart:math' as math;
import 'dart:typed_data';

import 'hooks.dart';
import 'line_filters.dart';

/// The numbers that drive `StrokeShaper` for one pen and stroke, derived
/// from the pen's width and stabiliser and the stroke's [unit]
/// (`OutlineSpec.paramsFor`). Everything is in world units or samples of
/// [step].
///
/// Two kinds of scale meet here. The *pen's motion* (digitiser jitter,
/// hooks, what counts as a cusp) happens on the screen, so position
/// smoothing, corners and hooks scale with [unit], the world size of a
/// screen pixel when the stroke was written. The *ink's shape* (radius
/// smoothing, end rules) scales with the width.
class ShapeParams {
  ShapeParams({
    required this.width,
    required this.unit,
    required double streamline,
    required double radiusSigma,
    required double maxRadiusSlope,
    required double settleReach,
    required double levelReach,
    required double tipReach,
    required this.taperStart,
    required this.taperEnd,
  }) : dedupe = math.max(0.01 * unit, math.min(0.01, width * 0.02)) {
    // The pen's width on screen, and smoothing that grows a little with it
    // (detail finer than a wide pen is invisible anyway).
    final screenWidth = width / unit;
    final boost = (screenWidth / 2.5).clamp(0.85, 1.6);
    // Never 0: at stabiliser 0 it removes the digitiser's sub-pixel jitter
    // and keeps every visible detail (cusps are corners, which smoothing
    // never crosses); it grows with the stabiliser.
    sigma = (0.7 + 0.8 * streamline) * boost * unit;
    step = (sigma / 3).clamp(0.15 * unit, 0.6 * unit);
    cornerBaseline = (0.4 * screenWidth).clamp(0.5, 2.0) * unit;
    hooks = HookFinder(screenWidth, unit: unit);
    kernel = LineFilters.lowPassKernel(sigma / step);
    kernelK = (kernel.length - 1) ~/ 2;
    fit = math.min(kernelK, math.max(2, (2 * sigma / step).ceil()));
    cornerK = math.max(1, (cornerBaseline / step).ceil());
    radiusKeep = math.exp(-2 * step / radiusSigma);
    slope = maxRadiusSlope * step;
    settleK = (settleReach / step).ceil();
    levelK = (levelReach / step).ceil();
    settleEndK = (math.min(settleReach, tipReach) / step).ceil();
    levelEndK = (math.min(levelReach, tipReach) / step).ceil();
    startReach = math.max(settleK, levelK) + (taperStart / step).ceil() + 1;
    endReach = math.max(settleEndK, levelEndK) + 1;
  }

  final double width;

  /// World units per screen pixel when the stroke was written (estimated
  /// from its points, `StrokeOutline.unitOf`).
  final double unit;

  /// Standard deviation of the position smoothing.
  late final double sigma;

  /// Spacing of the resampled centre line.
  late final double step;

  /// Pen-down/up hook rules.
  late final HookFinder hooks;

  /// Input points closer than this to the previous one are merged.
  final double dedupe;

  /// Position low-pass kernel and its half-width (samples).
  late final Float64List kernel;
  late final int kernelK;

  /// Samples of the quadratic fit that continues a stretch past its end.
  late final int fit;

  /// Corners: the line turns by more than [minTurn] between the directions
  /// [cornerK] samples (about [cornerBaseline]) before and after a sample.
  late final int cornerK;
  late final double cornerBaseline;
  static const double minTurn = 100 * math.pi / 180;

  /// Radius smoothing: weight kept per step, and the largest change.
  late final double radiusKeep;
  late final double slope;

  /// End rules (samples): non-swelling and levelled start and end.
  late final int settleK;
  late final int levelK;
  late final int settleEndK;
  late final int levelEndK;

  /// Tapers (world units).
  final double taperStart, taperEnd;

  /// Samples at the start / end that the end rules may still change.
  late final int startReach;
  late final int endReach;
}
