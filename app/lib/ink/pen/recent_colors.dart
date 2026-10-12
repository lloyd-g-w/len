/// The colours recently picked for quick colour slots: distinct opaque
/// ARGB values, most recent first, at most [max].
abstract final class RecentColors {
  static const int max = 8;

  /// [recent] with [argb] (made opaque) in front; [recent] itself when it
  /// is already the most recent.
  static List<int> add(List<int> recent, int argb) {
    final color = argb | 0xFF000000;
    if (recent.isNotEmpty && recent.first == color) return recent;
    return List.unmodifiable([color, ...recent.where((c) => c != color)].take(max));
  }

  /// Parses a list saved as is, strictly: null unless it holds at most
  /// [max] distinct opaque colours.
  static List<int>? parse(Object? json) {
    if (json is! List || json.length > max || json.toSet().length != json.length) return null;
    if (!json.every((c) => c is int && c >>> 24 == 0xFF)) return null;
    return List.unmodifiable(json.cast<int>());
  }
}
