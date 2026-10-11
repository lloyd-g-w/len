import 'dart:math' as math;
import 'dart:typed_data';

import 'line_filters.dart';

/// The numbers that drive `StrokeShaper` for one pen, derived from its
/// width and stabiliser (`OutlineSpec.params`). Everything is in world
/// units or samples of [step].
class ShapeParams {
  ShapeParams({
    required this.width,
    required double sigma,
    required double radiusSigma,
    required double maxRadiusSlope,
    required double settleReach,
    required double levelReach,
    required this.taperStart,
    required this.taperEnd,
  }) : step = (sigma / 3).clamp(0.15, 0.6),
       dedupe = math.max(0.01, width * 0.02) {
    kernel = LineFilters.lowPassKernel(sigma / step);
    kernelK = (kernel.length - 1) ~/ 2;
    fit = math.min(kernelK, math.max(2, (2 * sigma / step).ceil()));
    cornerK = math.max(1, (cornerBaseline / step).ceil());
    radiusKeep = math.exp(-2 * step / radiusSigma);
    slope = maxRadiusSlope * step;
    settleK = (settleReach / step).ceil();
    levelK = (levelReach / step).ceil();
    // At the moving end the rules must stay within the tip region (they
    // change ink there as the pen moves on): half a width at most.
    final tip = 0.5 * width;
    settleEndK = (math.min(settleReach, tip) / step).ceil();
    levelEndK = (math.min(levelReach, tip) / step).ceil();
    startReach = math.max(settleK, levelK) + (taperStart / step).ceil() + 1;
    endReach = math.max(settleEndK, levelEndK) + 1;
  }

  final double width;

  /// Spacing of the resampled centre line.
  final double step;

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
  double get cornerBaseline => (0.4 * width).clamp(0.5, 2.0);
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
