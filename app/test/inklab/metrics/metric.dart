import 'dart:ui';

/// One measured quality figure with its pass limit.
class Metric {
  const Metric(
    this.id,
    this.value, {
    required this.limit,
    this.unit = '',
    this.higherIsBetter = false,
    this.where,
    this.note = '',
  });

  /// `group.name`, e.g. `fidelity.hausdorff`.
  final String id;
  final double value;
  final double limit;
  final String unit;
  final bool higherIsBetter;

  /// Where (logical screen px) the worst value was found, if anywhere.
  final Offset? where;
  final String note;

  String get group => id.split('.').first;

  bool get pass => value.isNaN || (higherIsBetter ? value >= limit : value <= limit);

  String get formatted => '${_fmt(value)}$unit (limit ${_fmt(limit)}$unit)';

  static String _fmt(double v) {
    if (v.isNaN) return '–';
    if (v == v.roundToDouble() && v.abs() < 1e6) return v.toStringAsFixed(0);
    return v.abs() >= 100 ? v.toStringAsFixed(0) : v.toStringAsPrecision(3);
  }

  @override
  String toString() => '$id = $formatted ${pass ? 'ok' : 'FAIL'}';
}

/// The worst of several values, remembering where it was.
class Worst {
  double value = 0;
  Offset? where;

  void add(double v, [Offset? at]) {
    if (v > value) {
      value = v;
      where = at;
    }
  }
}

/// Limits scale with the stabiliser: [tight] at 0, [mid] at the default
/// 0.4, [loose] at 1 (linear in between).
double byStabiliser(double streamline, double tight, double mid, double loose) => streamline <= 0.4
    ? tight + (mid - tight) * streamline / 0.4
    : mid + (loose - mid) * (streamline - 0.4) / 0.6;
