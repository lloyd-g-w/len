import 'dart:typed_data';

import 'package:flutter/painting.dart';

import '../../domain/stroke.dart';
import '../render/shape_params.dart';
import '../render/stroke_outline.dart';
import '../render/stroke_renderer.dart';
import '../tool_settings.dart';
import '../viewport.dart';
import 'live_ink.dart';
import 'point_spacing.dart';
import 'pressure_filter.dart';

/// Where a platform overlay may draw the stroke being written, and the
/// view it is written in (logical px, in the drawing surface's own
/// coordinates).
class WetInkView {
  const WetInkView({required this.clip, required this.scale, required this.offset});

  /// The writing area of [viewport]: the surface less the [covered] edges
  /// (toolbars over it), and only the page on a page (its
  /// `contentBounds`, where committed ink is clipped too).
  factory WetInkView.of(ViewportController viewport, {EdgeInsets covered = EdgeInsets.zero}) {
    var clip = covered.deflateRect(Offset.zero & viewport.size);
    final page = viewport.contentBounds;
    if (page != null) {
      clip = clip.intersect(
        Rect.fromPoints(viewport.toScreen(page.topLeft), viewport.toScreen(page.bottomRight)),
      );
    }
    return WetInkView(clip: clip, scale: viewport.scale, offset: viewport.offset);
  }

  /// The overlay draws only inside this rectangle.
  final Rect clip;

  /// The view transform (`screen = world * scale + offset`): the overlay
  /// stops when it changes during a stroke.
  final double scale;
  final Offset offset;

  /// Whether [other] shows the world the same way.
  bool sameTransform(WetInkView other) => other.scale == scale && other.offset == offset;
}

/// How a platform overlay should draw the tip of the stroke being written
/// ("low-latency ink"): it paints the newest samples itself, before Flutter
/// can, until Flutter's own rendering of the live stroke catches up.
///
/// Only opaque pen ink qualifies — anywhere the overlay and Flutter's ink
/// overlap must look the same, which translucent (or flat-capped
/// highlighter) ink would not.
class WetInkStyle {
  const WetInkStyle({required this.color, required this.radii, required this.shape});

  /// Opaque ARGB colour.
  final int color;

  /// Outline radius in logical screen pixels at pressures 0, 0.1, … 1
  /// ([steps] + 1 values); the overlay interpolates between them.
  final List<double> radii;

  /// The geometry rules the overlay applies (logical screen pixels), the
  /// same as Flutter's outline so both draw the same ink.
  final WetInkShape shape;

  static const int steps = 10;

  /// The style of [live]'s stroke seen at viewport [scale], or null when it
  /// cannot be drawn faithfully by an overlay (or is not a free-hand stroke).
  static WetInkStyle? of(LiveInk live, double scale) {
    if (!live.isDrawing || live.straightened) return null;
    return forPen(live.tool, live.width, live.style, color: live.color, scale: scale);
  }

  /// The style the next stroke on a surface seen at viewport [scale] will
  /// have, if the stylus touches down now and draws ink (the pen tool),
  /// else null.
  static WetInkStyle? forNextStroke(ToolSettings tools, double scale) {
    if (tools.tool != EditorTool.pen) return null;
    final ink = tools.activeInk;
    final config = tools.configOf(ink);
    return forPen(
      ink,
      config.width,
      tools.styleFor(ink).copyWith(unit: 1 / scale),
      color: config.color,
      scale: scale,
    );
  }

  /// The style of ink drawn with [tool], [width] and [style] (with the
  /// zoom it is written at, `StrokeStyle.unit`) at viewport [scale], or
  /// null when an overlay cannot draw it faithfully.
  static WetInkStyle? forPen(
    InkTool tool,
    double width,
    StrokeStyle style, {
    required int color,
    required double scale,
  }) {
    final opaque = style.opacity >= 1 && (color >>> 24) == 0xFF;
    if (!opaque || tool.isHighlighter) return null;
    final spec = StrokeRenderer.specFor(tool, width, style);
    return WetInkStyle(
      color: color,
      radii: [for (var i = 0; i <= steps; i++) spec.radiusFor(i / steps) * scale],
      shape: WetInkShape.of(spec, scale, StrokeOutline.unitOf(const [], spec)),
    );
  }
}

/// The rules (beyond the radius table) that shape Flutter's ink near the pen
/// tip, for an overlay to follow: which samples become points, how the
/// pressure and radius are smoothed, the end rules and the pen-down and
/// pen-up hooks. In
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
    required this.hookStart,
    required this.hookEnd,
    required this.hookBody,
    required this.hookLocal,
    required this.step,
    required this.dedupe,
    required this.kernel,
    required this.fit,
    required this.cornerK,
    required this.lag,
    required this.startReach,
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
      hookStart: hooks.maxStart * scale,
      hookEnd: hooks.maxEnd * scale,
      hookBody: hooks.body * scale,
      hookLocal: hooks.local * scale,
      step: params.step * scale,
      dedupe: params.dedupe * scale,
      kernel: params.kernel,
      fit: params.fit,
      cornerK: params.cornerK,
      lag: params.lag,
      startReach: params.startReach,
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

  /// Pen-down and pen-up hook rules (see `HookFinder`).
  final double hookStart, hookEnd, hookBody, hookLocal;

  /// Position smoothing (see `StrokeShaper`): resampling step, merge
  /// distance, low-pass kernel (per sample), samples of the end fit, and
  /// the corner baseline in samples.
  final double step, dedupe;
  final List<double> kernel;
  final int fit, cornerK;

  /// With the stabiliser on, live ink shows only the final line (see
  /// `ShapeParams.lag`): how many samples the tip rules keep back, and the
  /// start rules' reach (samples); [lag] is 0 with the stabiliser off.
  final int lag, startReach;

  /// The outline's position rules for points in these units.
  ShapeParams get positions => ShapeParams.positionsOf(
    ShapeParams.explicit(
      step: step,
      dedupe: dedupe,
      kernel: kernel,
      fit: fit,
      cornerK: cornerK,
      lag: lag,
      startReach: startReach,
    ),
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
    hookStart: hookStart * f,
    hookEnd: hookEnd * f,
    hookBody: hookBody * f,
    hookLocal: hookLocal * f,
    step: step * f,
    dedupe: dedupe * f,
    kernel: kernel,
    fit: fit,
    cornerK: cornerK,
    lag: lag,
    startReach: startReach,
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
    hookStart,
    hookEnd,
    hookBody,
    hookLocal,
    step,
    dedupe,
    fit.toDouble(),
    cornerK.toDouble(),
    lag.toDouble(),
    startReach.toDouble(),
    ...kernel,
  ]);
}
