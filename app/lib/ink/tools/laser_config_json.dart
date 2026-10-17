import 'laser_config.dart';

/// Parsing of saved [LaserConfig]s: a part missing or malformed takes its
/// default. The quick colours go with their selection (a list of
/// [LaserConfig.minSlots]..[LaserConfig.maxSlots] opaque colours and an
/// index into it), as do the sizes (in [LaserConfig.minSize]..
/// [LaserConfig.maxSize]); durations are clamped to their ranges.
abstract final class LaserConfigJson {
  static LaserConfig parse(Object? json) {
    if (json is! Map) return const LaserConfig();
    final colors = _list(json['colors'], (c) => c is int && c >>> 24 == 0xFF ? c : null);
    final colorIndex = _index(json['color'], colors);
    final sizes = _list(json['sizes'], (s) {
      final v = s is num && s.isFinite ? s.toDouble() : null;
      return v != null && v >= LaserConfig.minSize && v <= LaserConfig.maxSize ? v : null;
    });
    final sizeIndex = _index(json['size'], sizes);
    final colorsOk = colors != null && colorIndex != null;
    final sizesOk = sizes != null && sizeIndex != null;
    final duration = json['duration'];
    final hold = json['hold'];
    return LaserConfig(
      mode: LaserMode.parse(json['mode']),
      colors: colorsOk ? colors : LaserConfig.defaultColors,
      colorIndex: colorsOk ? colorIndex : 0,
      sizes: sizesOk ? sizes : LaserConfig.defaultSizes,
      sizeIndex: sizesOk ? sizeIndex : LaserConfig.defaultSizeIndex,
      duration: duration is int
          ? _clamp(duration, LaserConfig.minDuration, LaserConfig.maxDuration)
          : LaserConfig.defaultDuration,
      fade: LaserFade.parse(json['fade']),
      hold: hold is int
          ? _clamp(hold, LaserConfig.minHold, LaserConfig.maxHold)
          : LaserConfig.defaultHold,
    );
  }

  static Duration _clamp(int ms, Duration min, Duration max) =>
      Duration(milliseconds: ms.clamp(min.inMilliseconds, max.inMilliseconds));

  /// A list of [LaserConfig.minSlots]..[LaserConfig.maxSlots] valid items.
  static List<T>? _list<T>(Object? raw, T? Function(Object?) item) {
    if (raw is! List || raw.length < LaserConfig.minSlots || raw.length > LaserConfig.maxSlots) {
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
}
