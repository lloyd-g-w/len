import '../../domain/text/text_data.dart';

/// Where a text box flowing across pages continues on the next page, as
/// the editing field shows it (the whole chain in one field): at model
/// offset [at] (the next part's start) the field leaves [gap] (world
/// units) of room, from the bottom of the part before to the top of the
/// next, over the page edge. [soft]: the page ends inside a paragraph.
typedef FlowBreak = ({int at, double gap, bool soft});

/// What is inserted into the laid-out text at one model offset.
enum _Insert {
  /// A page break between paragraphs: the room's placeholder on a line of
  /// its own (the paragraph's own break ends the line before). Comes
  /// before the marker of the line it starts.
  page('\uFFFC\n'),

  /// A list marker's placeholder.
  marker('\uFFFC'),

  /// A wrapped list item's break and indent.
  wrap('\n\uFFFC'),

  /// A page break inside a paragraph.
  softPage('\n\uFFFC\n'),

  /// A page break inside a wrapped list item: the next line keeps its
  /// indent.
  wrapPage('\n\uFFFC\n\uFFFC');

  const _Insert(this.text);

  final String text;

  /// The first position inside it where the caret may not rest (it may
  /// rest before a line break, at the end of the line it ends).
  int get hiddenFrom => text.startsWith('\n') ? 1 : 0;
}

/// Maps offsets between a text box's text (model offsets) and the laid-out
/// (display) text, which inserts
///
/// - one placeholder character (U+FFFC) before each list line, where its
///   marker sits,
/// - at each *wrap* of a list item (see `TextWraps`) a line break plus a
///   placeholder as wide as the marker column ([wrapText]), so the
///   continuation line hangs under the item's text, and
/// - at each page break of a box flowing across pages ([FlowBreak], in the
///   editing field only) a line holding a placeholder as tall as the room
///   to the next page.
///
/// The model offset at a wrap or page break maps to the start of the
/// continuation line.
class MarkerOffsets {
  MarkerOffsets(TextData data, [List<int> wraps = const [], List<FlowBreak> breaks = const []])
    : _inserts = _merge(_listStarts(data), wraps, breaks);

  /// What is inserted at a wrap.
  static const String wrapText = '\n\uFFFC';

  /// Model offsets of the inserts, ascending.
  final List<({int at, _Insert kind})> _inserts;

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

  static List<({int at, _Insert kind})> _merge(
    List<int> markers,
    List<int> wraps,
    List<FlowBreak> breaks,
  ) {
    final soft = {
      for (final b in breaks)
        if (b.soft) b.at,
    };
    final wrapped = wraps.toSet();
    final out = [
      for (final b in breaks)
        if (!b.soft)
          (at: b.at, kind: _Insert.page)
        else if (!wrapped.contains(b.at))
          (at: b.at, kind: _Insert.softPage),
      for (final m in markers) (at: m, kind: _Insert.marker),
      for (final w in wraps) (at: w, kind: soft.contains(w) ? _Insert.wrapPage : _Insert.wrap),
    ];
    // A wrap or soft break is never at a line start, so only a page break
    // and a marker share an offset.
    out.sort((a, b) => a.at != b.at ? a.at.compareTo(b.at) : a.kind.index.compareTo(b.kind.index));
    return out;
  }

  bool get isEmpty => _inserts.isEmpty;

  /// Display offset of model offset [m]: after the marker of its line, and
  /// at a wrap or page break at the start of the continuation line.
  int toDisplay(int m) {
    var d = m;
    for (final i in _inserts) {
      if (i.at > m) break;
      d += i.kind.text.length;
    }
    return d;
  }

  /// Model offset of display offset [d] (inside an insert: its offset).
  int toModel(int d) {
    var shift = 0;
    for (final i in _inserts) {
      final start = i.at + shift;
      if (d <= start) break;
      if (d < start + i.kind.text.length) return i.at;
      shift += i.kind.text.length;
    }
    return d - shift;
  }

  /// The insert covering display character [d], if any.
  _Insert? _insertAt(int d) {
    var shift = 0;
    for (final i in _inserts) {
      final start = i.at + shift;
      if (d < start) return null;
      if (d < start + i.kind.text.length) return i.kind;
      shift += i.kind.text.length;
    }
    return null;
  }

  /// Whether display character [d] is a list marker.
  bool isMarker(int d) => _insertAt(d) == _Insert.marker;

  /// Whether display character [d] belongs to a wrap or a page break.
  bool isWrap(int d) {
    final kind = _insertAt(d);
    return kind != null && kind != _Insert.marker;
  }

  /// Whether display offset [d] lies inside a page break's insert (on the
  /// line of the room over a page edge, or just before it).
  bool isPageBreak(int d) {
    final kind = _insertAt(d);
    return kind == _Insert.page || kind == _Insert.softPage || kind == _Insert.wrapPage;
  }

  /// Whether the caret must not rest at display offset [d]: just before a
  /// marker, or inside a wrap's or page break's insert.
  bool isHidden(int d) {
    var shift = 0;
    for (final i in _inserts) {
      final start = i.at + shift;
      if (d < start) return false;
      final length = i.kind.text.length;
      if (d >= start + i.kind.hiddenFrom && d < start + length) return true;
      shift += length;
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
        ..write(i.kind.text);
      last = i.at;
    }
    out.write(text.substring(last));
    return out.toString();
  }
}
