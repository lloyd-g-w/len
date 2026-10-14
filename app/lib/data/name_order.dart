import 'search/search_query.dart';

/// The one A→Z order of names in the library (folders and notebooks alike):
/// Unicode case-insensitive and accent-insensitive, as search folds text, and
/// independent of the device's locale, so every list and every device agrees.
abstract final class NameOrder {
  /// The key names are compared by: lower case, Latin accents folded
  /// ([SearchText.fold]), combining marks dropped.
  static String key(String name) => SearchText.fold(name).replaceAll(_mark, '');

  static final _mark = RegExp(r'\p{M}', unicode: true);

  /// Compares [T]s (objects, not strings or records) by the [key] of their
  /// name, equal names by id. Keys are cached per item while the comparator
  /// lives, so create one per sort.
  static int Function(T, T) comparator<T>(String Function(T) nameOf, String Function(T) idOf) {
    final keys = Expando<String>();
    String keyOf(T item) => keys[item as Object] ??= key(nameOf(item));
    return (a, b) {
      final c = keyOf(a).compareTo(keyOf(b));
      return c != 0 ? c : idOf(a).compareTo(idOf(b));
    };
  }
}
