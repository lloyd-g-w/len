import '../../domain/text/text_data.dart';

/// Maps offsets between a text box's text (model offsets) and the laid-out
/// text, which has one placeholder character before each list line.
class MarkerOffsets {
  MarkerOffsets(TextData data) : _starts = _listStarts(data);

  /// Model offsets of the starts of list lines, ascending.
  final List<int> _starts;

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

  bool get isEmpty => _starts.isEmpty;

  /// Display offset of model offset [m]: after the marker of its line.
  int toDisplay(int m) {
    var n = 0;
    while (n < _starts.length && _starts[n] <= m) {
      n++;
    }
    return m + n;
  }

  /// Model offset of display offset [d] (a marker maps to its line start).
  int toModel(int d) {
    var n = 0;
    while (n < _starts.length && _starts[n] + n < d) {
      n++;
    }
    return d - n;
  }

  /// Whether display offset [d] is just before a marker.
  bool isBeforeMarker(int d) {
    for (var n = 0; n < _starts.length; n++) {
      if (_starts[n] + n == d) return true;
    }
    return false;
  }

  /// The laid-out text of [text].
  String display(String text) {
    if (_starts.isEmpty) return text;
    final out = StringBuffer();
    var last = 0;
    for (final s in _starts) {
      out
        ..write(text.substring(last, s))
        ..write('\uFFFC');
      last = s;
    }
    out.write(text.substring(last));
    return out.toString();
  }
}
