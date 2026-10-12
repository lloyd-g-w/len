import '../../domain/text/text_data.dart';

/// Maps offsets between a text box's text (model offsets) and the laid-out
/// (display) text, which inserts
///
/// - one placeholder character (U+FFFC) before each list line, where its
///   marker sits, and
/// - at each *wrap* of a list item (see `TextWraps`) a line break plus a
///   placeholder as wide as the marker column ([wrapText]), so the
///   continuation line hangs under the item's text.
///
/// The model offset at a wrap maps to the start of the continuation line.
class MarkerOffsets {
  MarkerOffsets(TextData data, [List<int> wraps = const []])
    : _inserts = _merge(_listStarts(data), wraps);

  /// What is inserted at a wrap.
  static const String wrapText = '\n\uFFFC';

  /// Model offsets of the inserts, ascending; `wrap` false = a marker.
  final List<({int at, bool wrap})> _inserts;

  static List<int> _listStarts(TextData data) {
    final out = <int>[];
    var start = 0;
    for (final p in data.paras) {
      if (p.isList) out.add(start);
      final nl = data.text.indexOf('\n', start);
      if (nl < 0) break;
      start = nl + 1;
    }
    return out;
  }

  static List<({int at, bool wrap})> _merge(List<int> markers, List<int> wraps) {
    final out = [
      for (final m in markers) (at: m, wrap: false),
      for (final w in wraps) (at: w, wrap: true),
    ];
    // A wrap is never at a line start, so offsets are unique.
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  static int _length(({int at, bool wrap}) i) => i.wrap ? wrapText.length : 1;

  bool get isEmpty => _inserts.isEmpty;

  /// Display offset of model offset [m]: after the marker of its line, and
  /// at a wrap at the start of the continuation line.
  int toDisplay(int m) {
    var d = m;
    for (final i in _inserts) {
      if (i.at > m) break;
      d += _length(i);
    }
    return d;
  }

  /// Model offset of display offset [d] (inside an insert: its offset).
  int toModel(int d) {
    var shift = 0;
    for (final i in _inserts) {
      final start = i.at + shift;
      if (d <= start) break;
      if (d < start + _length(i)) return i.at;
      shift += _length(i);
    }
    return d - shift;
  }

  /// The insert covering display character [d], if any.
  ({int at, bool wrap})? _insertAt(int d) {
    var shift = 0;
    for (final i in _inserts) {
      final start = i.at + shift;
      if (d < start) return null;
      if (d < start + _length(i)) return i;
      shift += _length(i);
    }
    return null;
  }

  /// Whether display character [d] is a list marker.
  bool isMarker(int d) => _insertAt(d)?.wrap == false;

  /// Whether display character [d] belongs to a wrap.
  bool isWrap(int d) => _insertAt(d)?.wrap == true;

  /// Whether the caret must not rest at display offset [d]: just before a
  /// marker, or between a wrap's break and its indent.
  bool isHidden(int d) {
    var shift = 0;
    for (final i in _inserts) {
      final start = i.at + shift;
      if (d < start) return false;
      if (d == (i.wrap ? start + 1 : start)) return true;
      shift += _length(i);
    }
    return false;
  }

  /// The laid-out text of [text].
  String display(String text) {
    if (_inserts.isEmpty) return text;
    final out = StringBuffer();
    var last = 0;
    for (final i in _inserts) {
      out
        ..write(text.substring(last, i.at))
        ..write(i.wrap ? wrapText : '\uFFFC');
      last = i.at;
    }
    out.write(text.substring(last));
    return out.toString();
  }
}
