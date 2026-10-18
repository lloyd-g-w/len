/// A tolerant HTML tokenizer for clipboard fragments (no DOM): start and
/// end tags with attributes, text with entities decoded, and the Office
/// conditional comments Word uses for list markers (the one around its
/// row for misaligned table columns is skipped). Comments, doctype,
/// processing instructions and the content of `script`, `style`, `title`,
/// `head`-only elements and Word's `xml` islands are skipped.
library;

/// One token of [tokenizeHtml].
sealed class HtmlToken {
  const HtmlToken();
}

/// `<name attrs>` (name lower-cased; [selfClosing] for `<br/>` style).
class StartTag extends HtmlToken {
  const StartTag(this.name, this.attrs, {this.selfClosing = false});
  final String name;
  final Map<String, String> attrs;
  final bool selfClosing;
}

/// `</name>`.
class EndTag extends HtmlToken {
  const EndTag(this.name);
  final String name;
}

/// Character data with entities decoded (whitespace not yet collapsed).
class HtmlText extends HtmlToken {
  const HtmlText(this.text);
  final String text;
}

/// Word's `<![if !supportLists]>` (start) and `<![endif]>` (end).
class ListMarkerFence extends HtmlToken {
  const ListMarkerFence({required this.start});
  final bool start;
}

const _rawText = {'script', 'style', 'title', 'xml', 'template', 'noscript'};

final _tagName = RegExp(r'^</?([a-zA-Z][a-zA-Z0-9:_-]*)');
final _attr = RegExp(r'''([^\s=/>"']+)(?:\s*=\s*("[^"]*"|'[^']*'|[^\s>]+))?''');

/// Tokens of [html]; never throws.
List<HtmlToken> tokenizeHtml(String html) {
  final out = <HtmlToken>[];
  var i = 0;
  final n = html.length;
  String? lower;
  void text(int from, int to) {
    if (to > from) out.add(HtmlText(decodeEntities(html.substring(from, to))));
  }

  while (i < n) {
    final lt = html.indexOf('<', i);
    if (lt < 0) {
      text(i, n);
      break;
    }
    text(i, lt);
    if (html.startsWith('<!--', lt)) {
      final end = html.indexOf('-->', lt + 4);
      i = end < 0 ? n : end + 3;
      continue;
    }
    if (html.startsWith('<!', lt) || html.startsWith('<?', lt)) {
      final end = html.indexOf('>', lt);
      final body = html.substring(lt, end < 0 ? n : end).toLowerCase();
      if (body.contains('supportmisalignedcolumns')) {
        // Word's row of empty cells setting misaligned columns' widths.
        final close = html.indexOf('<![endif]>', lt);
        i = close < 0 ? n : close + 10;
        continue;
      }
      if (body.contains('supportlists')) out.add(const ListMarkerFence(start: true));
      if (body.startsWith('<![endif]')) out.add(const ListMarkerFence(start: false));
      i = end < 0 ? n : end + 1;
      continue;
    }
    final name = _tagName.firstMatch(html.substring(lt, (lt + 64).clamp(0, n)));
    if (name == null) {
      // A lone '<' is text.
      text(lt, lt + 1);
      i = lt + 1;
      continue;
    }
    final end = _tagEnd(html, lt);
    final tag = name.group(1)!.toLowerCase();
    if (html.codeUnitAt(lt + 1) == 0x2F) {
      out.add(EndTag(tag));
      i = end;
      continue;
    }
    final inner = html.substring(lt + name.group(0)!.length, end - 1);
    out.add(StartTag(tag, _attrs(inner), selfClosing: inner.trimRight().endsWith('/')));
    i = end;
    if (_rawText.contains(tag)) {
      final close = (lower ??= html.toLowerCase()).indexOf('</$tag', i);
      if (close < 0) break;
      i = _tagEnd(html, close);
      out.add(EndTag(tag));
    }
  }
  return out;
}

/// The offset after the `>` closing the tag at [lt] (quotes respected).
int _tagEnd(String html, int lt) {
  int? quote;
  for (var i = lt + 1; i < html.length; i++) {
    final c = html.codeUnitAt(i);
    if (quote != null) {
      if (c == quote) quote = null;
    } else if (c == 0x22 || c == 0x27) {
      quote = c;
    } else if (c == 0x3E) {
      return i + 1;
    }
  }
  return html.length;
}

Map<String, String> _attrs(String s) => {
  for (final m in _attr.allMatches(s))
    m.group(1)!.toLowerCase(): decodeEntities(_unquote(m.group(2) ?? '')),
};

String _unquote(String v) =>
    v.length >= 2 && (v[0] == '"' || v[0] == "'") && v[v.length - 1] == v[0]
    ? v.substring(1, v.length - 1)
    : v;

const _named = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': '\u00A0',
  'ensp': '\u2002',
  'emsp': '\u2003',
  'thinsp': '\u2009',
  'ndash': '–',
  'mdash': '—',
  'hellip': '…',
  'lsquo': '‘',
  'rsquo': '’',
  'sbquo': '‚',
  'ldquo': '“',
  'rdquo': '”',
  'bdquo': '„',
  'laquo': '«',
  'raquo': '»',
  'bull': '•',
  'middot': '·',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'euro': '€',
  'pound': '£',
  'yen': '¥',
  'cent': '¢',
  'sect': '§',
  'para': '¶',
  'deg': '°',
  'plusmn': '±',
  'times': '×',
  'divide': '÷',
  'frac12': '½',
  'frac14': '¼',
  'frac34': '¾',
  'larr': '←',
  'rarr': '→',
  'uarr': '↑',
  'darr': '↓',
  'check': '✓',
  'shy': '',
  'zwj': '\u200D',
  'zwnj': '\u200C',
};

final _entity = RegExp(r'&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z][a-zA-Z0-9]{1,31});?');

/// [s] with character references (`&amp;`, `&#233;`, `&#x1F600;`) decoded;
/// unknown ones are kept as written.
String decodeEntities(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(_entity, (m) {
    final e = m.group(1)!;
    if (e.startsWith('#')) {
      final hex = e.length > 1 && (e[1] == 'x' || e[1] == 'X');
      final code = int.tryParse(e.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
      if (code == null || code <= 0 || code > 0x10FFFF || (code >= 0xD800 && code < 0xE000)) {
        return '\uFFFD';
      }
      return String.fromCharCode(code);
    }
    return _named[e] ?? _named[e.toLowerCase()] ?? m.group(0)!;
  });
}
