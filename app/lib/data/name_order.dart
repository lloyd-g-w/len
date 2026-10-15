import 'search/search_query.dart';

/// The one A→Z order of names in the library (folders and notebooks alike):
/// Unicode case-insensitive and accent-insensitive, as search folds text,
/// numbers by value ("Lecture 2" before "Lecture 10", UX_AUDIT R16-1), and
/// independent of the device's locale, so every list and every device agrees.
abstract final class NameOrder {
  /// The key names are compared by: lower case, Latin accents folded
  /// ([SearchText.fold]), combining marks dropped.
  static String key(String name) => SearchText.fold(name).replaceAll(_mark, '');

  static final _mark = RegExp(r'\p{M}', unicode: true);

  /// Compares two [key]s: runs of ASCII digits by their value (then the
  /// shorter run first, so "2" < "02"), everything else by code unit.
  static int compareKeys(String a, String b) {
    var i = 0, j = 0;
    while (i < a.length && j < b.length) {
      final ca = a.codeUnitAt(i), cb = b.codeUnitAt(j);
      if (_isDigit(ca) && _isDigit(cb)) {
        final ea = _digitsEnd(a, i), eb = _digitsEnd(b, j);
        // Leading zeros don't change the value.
        var sa = i, sb = j;
        while (sa < ea - 1 && a.codeUnitAt(sa) == _zero) {
          sa++;
        }
        while (sb < eb - 1 && b.codeUnitAt(sb) == _zero) {
          sb++;
        }
        final byLength = (ea - sa) - (eb - sb);
        if (byLength != 0) return byLength;
        final byDigits = a.substring(sa, ea).compareTo(b.substring(sb, eb));
        if (byDigits != 0) return byDigits;
        final byRun = (ea - i) - (eb - j);
        if (byRun != 0) return byRun;
        i = ea;
        j = eb;
        continue;
      }
      if (ca != cb) return ca - cb;
      i++;
      j++;
    }
    return (a.length - i) - (b.length - j);
  }

  static const int _zero = 0x30;
  static bool _isDigit(int c) => c >= _zero && c <= 0x39;
  static int _digitsEnd(String s, int from) {
    var end = from;
    while (end < s.length && _isDigit(s.codeUnitAt(end))) {
      end++;
    }
    return end;
  }

  /// Compares [T]s (objects, not strings or records) by the [key] of their
  /// name ([compareKeys]), equal names by id. Keys are cached per item
  /// while the comparator lives, so create one per sort.
  static int Function(T, T) comparator<T>(String Function(T) nameOf, String Function(T) idOf) {
    final keys = Expando<String>();
    String keyOf(T item) => keys[item as Object] ??= key(nameOf(item));
    return (a, b) {
      final c = compareKeys(keyOf(a), keyOf(b));
      return c != 0 ? c : idOf(a).compareTo(idOf(b));
    };
  }
}
