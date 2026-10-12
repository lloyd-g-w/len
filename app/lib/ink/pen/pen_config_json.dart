import '../../domain/stroke.dart';
import 'pen_config.dart';
import 'pen_defaults.dart';

/// Strict parsing of saved [PenConfig]s: every field must be present and
/// valid (opaque colours, widths in the ink's range, selections in range,
/// feel settings in theirs), else the whole config is rejected.
abstract final class PenConfigJson {
  static PenConfig? parse(Object? json, {required InkTool tool}) {
    if (json is! Map<String, Object?>) return null;
    final defaults = PenDefaults.of(tool);
    final colors = _list(json['colors'], (c) => c is int && c >>> 24 == 0xFF ? c : null);
    final widths = _list(json['widths'], (w) {
      final v = _number(w);
      return v != null && v >= defaults.minWidth && v <= defaults.maxWidth ? v : null;
    });
    final color = _index(json['color'], colors);
    final width = _index(json['width'], widths);
    final opacity = _unit(json['opacity'], min: PenConfig.minOpacity);
    final thinning = _unit(json['thinning']);
    final streamline = _unit(json['streamline']);
    final straight = json['straight'];
    if (colors == null ||
        widths == null ||
        color == null ||
        width == null ||
        opacity == null ||
        thinning == null ||
        streamline == null ||
        straight is! bool) {
      return null;
    }
    return PenConfig(
      colors: colors,
      widths: widths,
      colorIndex: color,
      widthIndex: width,
      opacity: opacity,
      thinning: thinning,
      streamline: streamline,
      straight: straight,
    );
  }

  /// A list of [PenConfig.minSlots]..[PenConfig.maxSlots] valid items.
  static List<T>? _list<T>(Object? raw, T? Function(Object?) item) {
    if (raw is! List || raw.length < PenConfig.minSlots || raw.length > PenConfig.maxSlots) {
      return null;
    }
    final items = <T>[];
    for (final r in raw) {
      final v = item(r);
      if (v == null) return null;
      items.add(v);
    }
    return items;
  }

  static int? _index(Object? raw, List<Object?>? list) =>
      list != null && raw is int && raw >= 0 && raw < list.length ? raw : null;

  static double? _number(Object? raw) => raw is num && raw.isFinite ? raw.toDouble() : null;

  static double? _unit(Object? raw, {double min = 0}) {
    final v = _number(raw);
    return v != null && v >= min && v <= 1 ? v : null;
  }
}
