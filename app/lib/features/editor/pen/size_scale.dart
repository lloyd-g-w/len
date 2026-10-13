import 'dart:math' as math;

import '../../../ink/tool_settings.dart';

/// A size slider's scale for an ink's widths: logarithmic, so fine pens
/// get as much travel as broad ones (the default sizes sit near the
/// middle). Slider values run 0..1; widths snap to 0.1 world units.
class SizeScale {
  SizeScale(PenDefaults d) : _min = d.minWidth, _max = d.maxWidth;

  final double _min, _max;

  double get _span => math.log(_max / _min);

  /// The slider position (0..1) of [width].
  double toSlider(double width) => math.log(width.clamp(_min, _max) / _min) / _span;

  /// The width at slider position [t] (0..1).
  double toWidth(double t) =>
      (_min * math.exp(t * _span) * 10).roundToDouble().clamp(_min * 10, _max * 10) / 10;
}
