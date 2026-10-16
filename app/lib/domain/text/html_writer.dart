import 'dart:ui' show TextDirection;

import 'html_css.dart';
import 'text_data.dart';

/// Formatted text as an HTML fragment for other apps (Google Docs, Word,
/// mail, Notion), the inverse of `textFromHtml`: bold, italic, underline
/// and strikethrough as tags; colours that are not grey, highlights
/// (blended onto white, as Len's are translucent) and fonts other than
/// Inter as inline styles; headings as h1 / h2; bulleted, numbered and
/// checklist items as nested lists (a checklist item is
/// `<li role="checkbox" aria-checked>` with a ☐ / ☑ marked `aria-hidden`,
/// so apps without checklists still show it); one block per line, spaces
/// kept with `&nbsp;` where HTML would collapse them; alignment as
/// `text-align`. Sizes are left to the receiving app (headings carry
/// theirs). Several [boxes] are separated by an empty line.
String htmlFromTexts(Iterable<TextData> boxes) {
  final out = StringBuffer();
  var first = true;
  for (final box in boxes) {
    if (!first) out.write('<div><br></div>');
    first = false;
    _BoxWriter(box, out).write();
  }
  return out.toString();
}

/// [htmlFromTexts] of one box.
String htmlFromText(TextData data) => htmlFromTexts([data]);

/// The text colour [argb] as written to HTML (opaque), or null where it
/// is written as none: transparent or grey (`textFromHtml` drops greys
/// too, so black text stays the receiving app's text colour).
int? htmlTextColor(int argb) {
  if (_alpha(argb) == 0) return null;
  final rgb = argb & 0xFFFFFF;
  return isGreyish(rgb) ? null : 0xFF000000 + rgb;
}

/// The highlight [argb] as written to HTML: blended onto white (opaque, as
/// not every app reads `rgba()`), or null where it is written as none.
int? htmlHighlight(int argb) {
  final a = _alpha(argb);
  if (a == 0) return null;
  int channel(int shift) =>
      (((argb & 0xFFFFFF) >> shift & 0xFF) * a + 255 * (255 - a) + 127) ~/ 255;
  final rgb = channel(16) * 0x10000 + channel(8) * 0x100 + channel(0);
  return isGreyish(rgb) ? null : 0xFF000000 + rgb;
}

// (No shifts of 32-bit values: web ints.)
int _alpha(int argb) => argb ~/ 0x1000000 & 0xFF;

/// The CSS font stack of [font] (null for Inter: the receiving app's own).
String? _family(TextFont font) => switch (font) {
  TextFont.inter => null,
  TextFont.lora => "'Lora',Georgia,serif",
  TextFont.mono => "'JetBrains Mono',Consolas,'Courier New',monospace",
  TextFont.caveat => "'Caveat',cursive",
};

String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// An open list: its kind and whether its last item is still open.
class _OpenList {
  _OpenList(this.kind);
  final ListKind kind;
  bool itemOpen = false;
}

class _BoxWriter {
  _BoxWriter(this.data, this.out);

  final TextData data;
  final StringBuffer out;
  final _lists = <_OpenList>[];
  late final List<SpanStyle> _styles = data.charStyles();

  /// Each paragraph's direction (its first strong character's).
  late final List<TextDirection> _dirs = data.directions;

  /// The current paragraph's direction and alignment as attributes. Start
  /// and end become left / right (apps such as Word ignore CSS's logical
  /// keywords); right-to-left paragraphs say so.
  String _attrs(int i) {
    final rtl = _dirs[i] == TextDirection.rtl;
    final align = switch (data.align) {
      TextAlignment.start => null,
      TextAlignment.center => 'center',
      TextAlignment.end => rtl ? 'left' : 'right',
    };
    return '${rtl ? ' dir="rtl"' : ''}${align == null ? '' : ' style="text-align:$align"'}';
  }

  void write() {
    final paras = data.paras;
    var start = 0;
    for (final (i, line) in data.text.split('\n').indexed) {
      final p = paras[i];
      if (p.isList) {
        _item(p, i);
      } else {
        _closeLists(0);
      }
      final tag = switch (p.heading) {
        1 => 'h1',
        2 => 'h2',
        _ => p.isList ? null : 'div',
      };
      if (tag != null) out.write('<$tag${p.isList ? '' : _attrs(i)}>');
      if (p.list == ListKind.check) {
        out.write('<span aria-hidden="true">${p.checked ? '☑' : '☐'} </span>');
      }
      _line(start, start + line.length);
      if (tag != null) out.write('</$tag>');
      start += line.length + 1;
    }
    _closeLists(0);
  }

  /// Opens the list item of [p], closing and opening lists to its level.
  void _item(ParaStyle p, int i) {
    final level = p.indent;
    _closeLists(level + 1);
    if (_lists.length == level + 1 && _lists.last.kind != p.list) _closeLists(level);
    if (_lists.length == level + 1 && _lists.last.itemOpen) out.write('</li>');
    while (_lists.length < level + 1) {
      out.write(switch (p.list) {
        ListKind.number => '<ol>',
        ListKind.check => '<ul style="list-style-type:none">',
        _ => '<ul>',
      });
      _lists.add(_OpenList(p.list));
    }
    final check = p.list == ListKind.check ? ' role="checkbox" aria-checked="${p.checked}"' : '';
    out.write('<li$check${_attrs(i)}>');
    _lists.last.itemOpen = true;
  }

  /// Closes lists deeper than [depth] (and their open items).
  void _closeLists(int depth) {
    while (_lists.length > depth) {
      final list = _lists.removeLast();
      if (list.itemOpen) out.write('</li>');
      out.write(list.kind == ListKind.number ? '</ol>' : '</ul>');
    }
  }

  /// The text of [start, end) as runs of one style each (`<br>` if empty).
  void _line(int start, int end) {
    if (start == end) {
      out.write('<br>');
      return;
    }
    var i = start;
    while (i < end) {
      final style = _styles[i];
      var j = i + 1;
      while (j < end && _styles[j] == style) {
        j++;
      }
      _run(i, j, style, start, end);
      i = j;
    }
  }

  void _run(int from, int to, SpanStyle s, int lineStart, int lineEnd) {
    final color = htmlTextColor(s.color ?? data.color);
    final highlight = s.highlight == null ? null : htmlHighlight(s.highlight!);
    final family = _family(s.font ?? data.font);
    final css = [
      if (color != null) 'color:${_hex(color)}',
      if (highlight != null) 'background-color:${_hex(highlight)}',
      if (family != null) 'font-family:$family',
    ];
    final tags = [if (s.bold) 'b', if (s.italic) 'i', if (s.underline) 'u', if (s.strike) 's'];
    if (css.isNotEmpty) out.write('<span style="${css.join(';')}">');
    for (final t in tags) {
      out.write('<$t>');
    }
    final text = data.text;
    for (var i = from; i < to; i++) {
      final c = text[i];
      switch (c) {
        case ' ':
          // A space HTML would collapse: at a line's ends or after another.
          final keep = i == lineStart || i == lineEnd - 1 || text[i - 1] == ' ';
          out.write(keep ? '&nbsp;' : ' ');
        case '\t':
          out.write('<span style="white-space:pre">\t</span>');
        case '&':
          out.write('&amp;');
        case '<':
          out.write('&lt;');
        case '>':
          out.write('&gt;');
        case '\u00A0':
          out.write('&nbsp;');
        default:
          out.write(c);
      }
    }
    for (final t in tags.reversed) {
      out.write('</$t>');
    }
    if (css.isNotEmpty) out.write('</span>');
  }
}
