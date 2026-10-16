import 'text_data.dart';

/// Strict reading of a text element's `data` from sync or an archive (see
/// SYNC_PROTOCOL.md, *Text boxes*): every field is required and must be
/// well-formed, so a malformed record is skipped as a whole instead of
/// showing a box that is not what its writer meant. `flow` is optional
/// (only a box continuing another has one) but strict when present
/// ([TextFlow.fromJson]). Unknown keys are ignored. (`TextData.fromJson` stays tolerant: it reads rows this app
/// wrote.)
abstract final class TextRecord {
  /// [json] as text data; throws [FormatException] if it is malformed.
  static TextData parse(Map<String, Object?> json) {
    final text = _field<String>(json, 'text');
    final size = _field<num>(json, 'size');
    if (!size.isFinite || size < TextData.minFontSize || size > TextData.maxFontSize) {
      _bad('size');
    }
    final color = _field<int>(json, 'color');
    if (color < 0 || color > 0xFFFFFFFF) _bad('color');
    final align = TextAlignment.tryParse(_field<String>(json, 'align')) ?? _bad('align');
    final font = TextFont.tryParse(_field<String>(json, 'font')) ?? _bad('font');
    final spans = [for (final s in _field<List<Object?>>(json, 'spans')) _span(s, text.length)];
    for (var i = 1; i < spans.length; i++) {
      if (spans[i].start < spans[i - 1].end) _bad('spans');
    }
    final paras = [for (final p in _field<List<Object?>>(json, 'paras')) _para(p)];
    if (paras.isNotEmpty && paras.length != '\n'.allMatches(text).length + 1) _bad('paras');
    // Only a box continuing another has a flow; when present it is strict.
    final flow = json.containsKey('flow') ? TextFlow.fromJson(json['flow']) ?? _bad('flow') : null;
    return TextData.rich(
      text: text,
      spans: spans,
      paras: paras,
      font: font,
      fontSize: size.toDouble(),
      color: color,
      align: align,
      autoWidth: _field<bool>(json, 'autoWidth'),
      flow: flow,
    );
  }

  static T _field<T>(Map<Object?, Object?> json, String key) {
    final value = json[key];
    if (value is T && json.containsKey(key)) return value;
    _bad(key);
  }

  static Never _bad(String key) => throw FormatException('Malformed text data: $key');

  static StyledRange _span(Object? s, int length) {
    if (s is! List || s.length != 3) _bad('spans');
    final [start, end, style] = s;
    if (start is! int || end is! int || style is! Map<String, Object?>) _bad('spans');
    if (start < 0 || end <= start || end > length) _bad('spans');
    return StyledRange(start, end, _style(style));
  }

  static SpanStyle _style(Map<String, Object?> json) {
    bool flag(String key) {
      if (!json.containsKey(key)) return false;
      return json[key] == true ? true : _bad('spans');
    }

    int? argb(String key) {
      final v = json[key];
      if (v == null && !json.containsKey(key)) return null;
      return v is int && v >= 0 && v <= 0xFFFFFFFF ? v : _bad('spans');
    }

    final size = json['sz'];
    if (json.containsKey('sz') && (size is! num || !size.isFinite || size <= 0)) _bad('spans');
    final font = json['f'];
    final style = SpanStyle(
      bold: flag('b'),
      italic: flag('i'),
      underline: flag('u'),
      strike: flag('s'),
      color: argb('c'),
      highlight: argb('hl'),
      size: (size as num?)?.toDouble(),
      font: font == null && !json.containsKey('f')
          ? null
          : TextFont.tryParse(font) ?? _bad('spans'),
    );
    if (style.isPlain) _bad('spans');
    return style;
  }

  static ParaStyle _para(Object? p) {
    if (p is! Map<String, Object?>) _bad('paras');
    final h = p['h'], l = p['l'], x = p['x'], n = p['n'];
    if (p.containsKey('h') && h != 1 && h != 2) _bad('paras');
    final list = p.containsKey('l')
        ? ListKind.values.firstWhere(
            (k) => k != ListKind.none && k.name == l,
            orElse: () => _bad('paras'),
          )
        : ListKind.none;
    if (p.containsKey('x') && (x != true || list != ListKind.check)) _bad('paras');
    if (p.containsKey('n') &&
        (n is! int || n < 1 || n > ParaStyle.maxIndent || list == ListKind.none)) {
      _bad('paras');
    }
    return ParaStyle(
      heading: (h as num?)?.toInt() ?? 0,
      list: list,
      checked: x == true,
      indent: n is int ? n : 0,
    );
  }
}
