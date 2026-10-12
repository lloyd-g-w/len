import 'html_css.dart';
import 'html_tokens.dart';
import 'text_data.dart';

/// Formatted text from HTML on the clipboard (browsers, Google Docs, Word,
/// LibreOffice): bold, italic, underline, strikethrough, colours that are
/// not grey, highlights, monospaced code, headings (h1 → heading 1, h2 and
/// h3 → heading 2), nested bulleted / numbered lists and checklists, one
/// line per paragraph, whitespace collapsed like a browser. Sizes and
/// fonts are the [box]'s. Returns null when there is no text.
TextData? textFromHtml(String html, TextData box) {
  final reader = _HtmlReader(box.font == TextFont.mono);
  for (final token in tokenizeHtml(fragmentOf(html))) {
    reader.add(token);
  }
  return reader.result(box);
}

/// The fragment of a clipboard HTML document: between Windows' / Firefox'
/// `<!--StartFragment-->` markers if present, past a `Version:0.9` CF_HTML
/// header otherwise.
String fragmentOf(String html) {
  final start = html.indexOf('<!--StartFragment');
  if (start >= 0) {
    final from = html.indexOf('-->', start);
    final end = html.indexOf('<!--EndFragment', from);
    if (from >= 0) return html.substring(from + 3, end < 0 ? html.length : end);
  }
  if (html.startsWith('Version:')) {
    final lt = html.indexOf('<');
    return lt < 0 ? '' : html.substring(lt);
  }
  return html;
}

const _void = {
  'br', 'img', 'input', 'hr', 'meta', 'link', 'wbr', 'col', 'area', 'base', 'source', 'embed', //
  'param', 'track',
};

const _blocks = {
  'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'ul', 'ol', 'blockquote', 'pre', //
  'table', 'tr', 'thead', 'tbody', 'tfoot', 'section', 'article', 'header', 'footer', 'nav',
  'aside', 'dl', 'dt', 'dd', 'figure', 'figcaption', 'main', 'address', 'hr', 'center', 'form',
  'fieldset', 'details', 'summary', 'body', 'html', 'caption', 'menu',
};

/// One line of the result.
class _Line {
  final text = StringBuffer();
  final chars = <SpanStyle>[];
  ParaStyle? para;
  bool? check;
  ListKind? wordKind;

  bool get isEmpty => chars.isEmpty;
}

class _HtmlReader {
  _HtmlReader(this.monoBox);

  final bool monoBox;
  final _stack = <ElementFormat>[];
  final _lines = [_Line()];
  bool _space = false;
  SpanStyle _spaceStyle = SpanStyle.plain;
  int _pre = 0;
  StringBuffer? _marker;

  _Line get _line => _lines.last;

  void add(HtmlToken token) {
    switch (token) {
      case ListMarkerFence(start: true):
        _marker = StringBuffer();
      case ListMarkerFence():
        final marker = _marker?.toString().trim();
        _marker = null;
        if (marker != null) {
          _line.wordKind = RegExp(r'^[0-9a-zA-Z]{1,5}[.)]$').hasMatch(marker)
              ? ListKind.number
              : ListKind.bullet;
        }
      case HtmlText(:final text):
        if (_marker != null) {
          _marker!.write(text);
        } else {
          _text(text);
        }
      case StartTag(:final name, :final attrs, :final selfClosing):
        _start(name, attrs, selfClosing);
      case EndTag(:final name):
        _end(name);
    }
  }

  void _start(String name, Map<String, String> attrs, bool selfClosing) {
    if (_marker != null) return;
    if (name == 'br') return _newLine();
    if (name == 'input' && attrs['type']?.toLowerCase() == 'checkbox') {
      _line.check = attrs.containsKey('checked');
      return;
    }
    if (name == 'td' || name == 'th') {
      if (!_line.isEmpty) _space = true;
    }
    if (name == 'li' || name == 'p') _closeOpen(name);
    if (_blocks.contains(name)) _softBreak();
    if (_void.contains(name) || selfClosing) return;
    final format = ElementFormat.of(name, attrs);
    _stack.add(format);
    if (format.pre) _pre++;
  }

  /// An unclosed `<li>` (or `<p>`) ends where the next one starts.
  void _closeOpen(String name) {
    for (var i = _stack.length - 1; i >= 0; i--) {
      final tag = _stack[i].tag;
      if (tag == name) return _popTo(i);
      if (tag == 'ul' || tag == 'ol' || (name == 'p' && tag != 'span')) return;
    }
  }

  void _end(String name) {
    if (_marker != null) return;
    for (var i = _stack.length - 1; i >= 0; i--) {
      if (_stack[i].tag == name) {
        _popTo(i);
        if (_blocks.contains(name)) _softBreak();
        return;
      }
    }
  }

  void _popTo(int i) {
    while (_stack.length > i) {
      if (_stack.removeLast().pre) _pre--;
    }
  }

  void _softBreak() {
    _space = false;
    if (!_line.isEmpty) _lines.add(_Line());
  }

  void _newLine() {
    _space = false;
    _lines.add(_Line());
  }

  void _text(String text) {
    final style = _style();
    for (final rune in text.runes) {
      final c = String.fromCharCode(rune);
      if (c == '\uFEFF' || c == '\u200B' || c == '\r') continue;
      if (_pre > 0 && c == '\n') {
        _newLine();
      } else if (_pre == 0 && (c == ' ' || c == '\n' || c == '\t' || c == '\f')) {
        if (!_line.isEmpty) {
          _space = true;
          _spaceStyle = style;
        }
      } else {
        if (_space) _emit(' ', _spaceStyle);
        _space = false;
        _emit(c == '\u00A0' ? ' ' : c, style);
      }
    }
  }

  void _emit(String c, SpanStyle style) {
    final line = _line;
    if (line.isEmpty) line.para ??= _para();
    line.text.write(c);
    for (var i = 0; i < c.length; i++) {
      line.chars.add(style);
    }
  }

  SpanStyle _style() {
    var bold = false, italic = false, underline = false, strike = false, mono = false;
    int? color, highlight;
    for (final f in _stack) {
      bold = f.bold ?? bold;
      italic = f.italic ?? italic;
      underline = underline || f.underline;
      strike = strike || f.strike;
      mono = mono || f.mono;
      color = f.color ?? color;
      highlight = f.highlight ?? highlight;
    }
    return SpanStyle(
      bold: bold,
      italic: italic,
      underline: underline,
      strike: strike,
      color: color,
      highlight: highlight,
      font: mono && !monoBox ? TextFont.mono : null,
    );
  }

  /// The paragraph style of the innermost heading and list item.
  ParaStyle _para() {
    var heading = 0, depth = 0, item = -1, level = -1;
    for (final (i, f) in _stack.indexed) {
      if (f.heading > 0) heading = f.heading;
      if (f.list != null) depth++;
      if (f.tag == 'li') item = i;
      if (f.listLevel != null) level = f.listLevel!;
    }
    if (item < 0 && level < 0) return ParaStyle(heading: heading);
    var kind = ListKind.bullet;
    var checked = false;
    if (item >= 0) {
      final li = _stack[item];
      for (var i = item - 1; i >= 0; i--) {
        if (_stack[i].list case final list?) {
          kind = list;
          break;
        }
      }
      if (li.checked != null) {
        kind = ListKind.check;
        checked = li.checked!;
      }
      level = li.listLevel ?? (depth - 1);
    }
    return ParaStyle(heading: heading, list: kind, checked: checked, indent: level);
  }

  TextData? result(TextData box) {
    final lines = [
      for (final l in _lines) (text: l.text.toString(), chars: l.chars, para: _finalPara(l)),
    ];
    while (lines.isNotEmpty && lines.last.text.trim().isEmpty) {
      lines.removeLast();
    }
    while (lines.isNotEmpty && lines.first.text.trim().isEmpty) {
      lines.removeAt(0);
    }
    if (lines.isEmpty) return null;
    final chars = <SpanStyle>[];
    for (final (i, l) in lines.indexed) {
      if (i > 0) chars.add(SpanStyle.plain);
      chars.addAll(l.chars);
    }
    return TextData.rich(
      text: lines.map((l) => l.text).join('\n'),
      spans: TextData.compact(chars),
      paras: [for (final l in lines) l.para],
      font: box.font,
      fontSize: box.fontSize,
      color: box.color,
      align: box.align,
      autoWidth: box.autoWidth,
    );
  }

  ParaStyle _finalPara(_Line l) {
    var p = l.para ?? ParaStyle.body;
    if (l.wordKind != null && p.isList) p = p.copyWith(list: l.wordKind);
    if (l.check != null) {
      p = p.copyWith(list: ListKind.check, checked: l.check, indent: p.isList ? p.indent : 0);
    }
    return p;
  }
}
