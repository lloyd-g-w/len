import 'dart:math' as math;
import 'dart:ui';

import '../../domain/stroke.dart';
import 'capsule_emitter.dart';
import 'catmull_rom.dart';
import 'centerline.dart';
import 'outline_sink.dart';

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

  /// Outline radius at [pressure]: half the [width] at medium pressure,
  /// thinner/thicker with lighter/harder pressure as [thinning] allows.
  double radiusFor(double pressure) {
    final t = (0.5 - thinning * (0.5 - pressure)).clamp(0.0, 1.0);
    return (width * easing(t)).clamp(math.min(0.25, width / 2), width);
  }

  // The stabiliser ([streamline], 0..1) is the single control for all
  // smoothing. At 0 the ink is the pen's raw path and pressure: nothing is
  // filtered beyond interpolating between samples.

  /// Standard deviation (world units) of the positional smoothing; 0 at
  /// stabiliser 0, scaled with the width so small handwriting keeps its
  /// shape.
  double get positionSigma => 2.0 * streamline * (width / 2).clamp(1.0, 3.0);

  /// Length scale of the (causal) radius smoothing: from half a width at
  /// stabiliser 0 (just digitiser noise) to several widths.
  double get radiusSigma => width * (0.5 + 6 * streamline);

  /// Spacing of the resampled centre line.
  double get sampleStep => (positionSigma / 2.5).clamp(0.25, 2.0);

  /// Fastest allowed change of the radius per unit of length.
  double get maxRadiusSlope => 0.6 - 0.45 * streamline;

  /// How far from a finished stroke's ends the pen-down/pen-up pressure ramp
  /// is levelled out (0 at stabiliser 0: the natural ramp is kept).
  double get levelReach => 2 * width * streamline;
}

/// A raw input sample: position and outline radius.
class _Sample {
  _Sample(this.x, this.y, this.r);
  final double x, y;
  double r;

  Offset get offset => Offset(x, y);
}

/// Builds filled outline paths for variable-width ink strokes.
///
/// Pipeline: drop duplicate samples → trim pen-lift hooks → densify along a
/// centripetal Catmull-Rom spline → resample at a
/// uniform arc-length spacing → Gaussian-smooth positions (ends pinned, so
/// there is no lag) and radii → limit how fast the radius may change →
/// make the ends non-swelling → apply tapers → emit the union of capsules
/// between consecutive samples ([CapsuleEmitter]).
abstract final class StrokeOutline {
  /// Builds the outline of [points]. [pressures], when given, overrides the
  /// per-point pressure (used for direction-dependent nibs). [complete] is
  /// false while the stroke is still being drawn: its moving end is then
  /// left untrimmed.
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
    var samples = _dedupe(points, pressures, spec);
    if (samples.isEmpty) return;
    if (samples.length > 3) {
      samples = _trimHook(samples, spec.width, atEnd: false);
      if (complete) samples = _trimHook(samples, spec.width, atEnd: true);
    }
    // Sparse samples from fast writing would otherwise be joined by straight
    // chords (faceted, "jittery" curves); a spline through them restores
    // the curve the pen actually travelled.
    final dense = CatmullRom.densify(
      [for (final s in samples) s.x],
      [for (final s in samples) s.y],
      [for (final s in samples) s.r],
      spec.sampleStep * 2,
    );
    final line = Centerline.resample(dense.x, dense.y, dense.r, spec.sampleStep)
      ..settleEnds(spec.width, end: complete)
      ..findCorners(spec.positionSigma)
      ..smoothPositions(spec.positionSigma)
      ..smoothRadii(spec.radiusSigma)
      ..limitRadiusSlope(spec.maxRadiusSlope)
      ..settleEnds(spec.width, end: complete)
      ..levelEnds(spec.levelReach, end: complete)
      ..taper(spec.taperStart, complete ? spec.taperEnd : 0);
    final maxR = line.r.fold<double>(0, math.max);
    if (line.length < 2 || line.arcLength < maxR * 0.5) {
      final r = math.max(samples.fold<double>(0, (m, s) => math.max(m, s.r)), 0.25);
      _dot(sink, line.x[0], line.y[0], r, spec.flatCaps);
      return;
    }
    CapsuleEmitter(line, flatCaps: spec.flatCaps).emit(sink);
  }

  static List<_Sample> _dedupe(
    List<StrokePoint> points,
    List<double>? pressures,
    OutlineSpec spec,
  ) {
    final eps = math.max(0.01, spec.width * 0.02);
    final out = <_Sample>[];
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final r = spec.radiusFor(pressures?[i] ?? p.pressure);
      if (out.isNotEmpty && (Offset(p.x, p.y) - out.last.offset).distance < eps) {
        out.last.r = math.max(out.last.r, r);
        continue;
      }
      out.add(_Sample(p.x, p.y, r));
    }
    return out;
  }

  /// Removes a short end segment that doubles back (the flick a pen makes
  /// as it lands or lifts), which would otherwise render as a nub. The cut
  /// is made at the furthest point (within a short reach of the end) where
  /// the remaining tail turns back by more than 90° against the body.
  static List<_Sample> _trimHook(List<_Sample> s, double width, {required bool atEnd}) {
    final maxHook = math.max(2.0, width * 1.2);
    final seq = atEnd ? s.reversed.toList() : s;
    var cut = 0;
    var length = 0.0;
    for (var j = 1; j + 3 < seq.length; j++) {
      length += (seq[j].offset - seq[j - 1].offset).distance;
      if (length > maxHook) break;
      final hook = seq[0].offset - seq[j].offset;
      final body = seq[j].offset - seq[j + 3].offset;
      if (hook.distance == 0 || body.distance == 0) continue;
      if (hook.dx * body.dx + hook.dy * body.dy < 0) cut = j;
    }
    if (cut == 0) return s;
    final kept = seq.sublist(cut);
    return atEnd ? kept.reversed.toList() : kept;
  }

  static void _dot(OutlineSink sink, double x, double y, double r, bool flat) {
    if (!flat) return addCircle(sink, x, y, r);
    sink
      ..moveTo(x - r, y - r)
      ..lineTo(x + r, y - r)
      ..lineTo(x + r, y + r)
      ..lineTo(x - r, y + r)
      ..close();
  }
}
