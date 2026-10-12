import '../../domain/stroke.dart';
import 'pen_config.dart';
import 'pen_defaults.dart';

/// Lenient parsing of saved [PenConfig]s: anything missing or invalid is
/// taken from the fallback, values are clamped to their ranges.
abstract final class PenConfigJson {
  static PenConfig parse(Object? json, PenConfig fallback, {required InkTool tool}) {
    if (json is! Map) return fallback;
    double unit(String key, double orElse, {double min = 0}) {
      final v = json[key];
      return v is num && v.isFinite ? v.toDouble().clamp(min, 1.0) : orElse;
    }

    final defaults = PenDefaults.of(tool);
    final slots = _slots(json, fallback, defaults);
    return slots.copyWith(
      opacity: tool.isHighlighter
          ? unit('opacity', fallback.opacity, min: PenConfig.minOpacity)
          : fallback.opacity,
      thinning: unit('thinning', fallback.thinning),
      streamline: unit('streamline', fallback.streamline),
    );
  }

  /// The colour and width rows and their selections.
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
