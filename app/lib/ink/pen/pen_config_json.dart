import '../../domain/stroke.dart';
import 'pen_config.dart';
import 'pen_defaults.dart';

/// Lenient parsing of saved [PenConfig]s, including the migration of the
/// older format that bundled a colour and a width into each of three
/// presets (`{"presets": [{"c": argb, "w": width}, …], "selected": i}`).
abstract final class PenConfigJson {
  static PenConfig parse(Object? json, PenConfig fallback, {required InkTool tool}) {
    if (json is! Map) return fallback;
    double unit(String key, double orElse, {double min = 0}) {
      final v = json[key];
      return v is num && v.isFinite ? v.toDouble().clamp(min, 1.0) : orElse;
    }

    final defaults = PenDefaults.of(tool);
    final slots = json.containsKey('colors') || json.containsKey('widths')
        ? _slots(json, fallback, defaults)
        : _migratePresets(json['presets'], json['selected'], fallback, defaults);
    final taper = json['taper'];
    return slots.copyWith(
      opacity: tool.isHighlighter
          ? unit('opacity', fallback.opacity, min: PenConfig.minOpacity)
          : fallback.opacity,
      thinning: unit('thinning', fallback.thinning),
      streamline: unit('streamline', fallback.streamline),
      taper: taper is bool ? taper : fallback.taper,
    );
  }

  /// The current format: separate colour and width rows.
  static PenConfig _slots(Map<Object?, Object?> json, PenConfig fallback, PenDefaults defaults) {
    final colors = _colors(json['colors']);
    final widths = _widths(json['widths'], defaults);
    final c = colors.isEmpty ? fallback.colors : colors;
    final w = widths.isEmpty ? fallback.widths : widths;
    return fallback.copyWith(
      colors: c,
      widths: w,
      colorIndex: _index(json['color'], c.length, colors.isEmpty ? fallback.colorIndex : 0),
      widthIndex: _index(json['width'], w.length, widths.isEmpty ? fallback.widthIndex : 0),
    );
  }

  /// Old presets: their colours become colour slots and their widths width
  /// slots (duplicates dropped), topped up from the defaults to three each.
  static PenConfig _migratePresets(
    Object? presets,
    Object? selected,
    PenConfig fallback,
    PenDefaults defaults,
  ) {
    if (presets is! List) return fallback;
    final valid = [
      for (final p in presets)
        if (p case {'c': final int c, 'w': final num w} when w.isFinite && w > 0)
          (color: (c & 0xFFFFFF) | 0xFF000000, width: defaults.clampWidth(w.toDouble())),
    ];
    if (valid.isEmpty) return fallback;
    final chosen =
        valid[selected is int && selected >= 0 && selected < valid.length ? selected : 0];
    final colors = valid.map((p) => p.color).toSet().toList();
    for (final c in defaults.colors) {
      if (colors.length >= 3) break;
      if (!colors.contains(c)) colors.add(c);
    }
    final widths = valid.map((p) => p.width).toSet().toList();
    for (final w in defaults.widths) {
      if (widths.length >= 3) break;
      if (widths.every((x) => (x - w).abs() > 0.05)) widths.add(w);
    }
    widths.sort();
    return fallback.copyWith(
      colors: colors,
      widths: widths,
      colorIndex: colors.indexOf(chosen.color),
      widthIndex: widths.indexOf(chosen.width),
    );
  }

  static List<int> _colors(Object? raw) => [
    if (raw is List)
      for (final c in raw.take(PenConfig.maxSlots))
        if (c is int) (c & 0xFFFFFF) | 0xFF000000,
  ];

  static List<double> _widths(Object? raw, PenDefaults defaults) => [
    if (raw is List)
      for (final w in raw.take(PenConfig.maxSlots))
        if (w is num && w.isFinite && w > 0) defaults.clampWidth(w.toDouble()),
  ];

  static int _index(Object? raw, int length, int orElse) =>
      raw is int && raw >= 0 && raw < length ? raw : orElse.clamp(0, length - 1);
}
