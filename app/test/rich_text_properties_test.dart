import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/html_text.dart';
import 'package:len/domain/text/rich_text_buffer.dart';
import 'package:len/domain/text/text_data.dart';

import 'support/property.dart';

const _box = TextData(fontSize: 20, font: TextFont.lora);

/// Characters edits insert: letters, diacritics, an emoji (a surrogate
/// pair), punctuation, spaces and line breaks.
const _alphabet = ['a', 'b', 'Z', 'é', 'ß', '😀', ' ', '.', '<', '&', '\n'];

String _string(math.Random r, int maxLength) =>
    [for (var i = r.nextInt(maxLength + 1); i > 0; i--) _alphabet[r.nextInt(_alphabet.length)]]
        .join();

/// An opaque colour that is not grey (`parseColor` drops greys).
int _colour(math.Random r) {
  while (true) {
    final c = [for (var i = 0; i < 3; i++) r.nextInt(256)];
    if (c.reduce(math.max) - c.reduce(math.min) >= 40) {
      return 0xFF000000 + c[0] * 0x10000 + c[1] * 0x100 + c[2];
    }
  }
}

SpanStyle _style(math.Random r, {bool sizes = true}) {
  if (r.nextInt(3) == 0) return SpanStyle.plain;
  return SpanStyle(
    bold: r.nextBool(),
    italic: r.nextBool(),
    underline: r.nextInt(4) == 0,
    strike: r.nextInt(4) == 0,
    color: r.nextInt(3) == 0 ? _colour(r) : null,
    highlight: r.nextInt(4) == 0 ? _colour(r) : null,
    size: sizes && r.nextInt(4) == 0 ? 8.0 + r.nextInt(30) : null,
    font: r.nextInt(4) == 0 ? (sizes ? TextFont.bundled[r.nextInt(4)] : TextFont.mono) : null,
  );
}

ParaStyle _para(math.Random r) {
  if (r.nextBool()) return ParaStyle.body;
  final list = ListKind.values[r.nextInt(ListKind.values.length)];
  return ParaStyle(
    heading: r.nextInt(3),
    list: list,
    checked: list == ListKind.check && r.nextBool(),
    indent: list == ListKind.none ? 0 : r.nextInt(ParaStyle.maxIndent + 1),
  );
}

/// Random formatted text.
TextData _data(math.Random r, {int maxLength = 30}) {
  final text = _string(r, maxLength);
  final chars = [for (var i = 0; i < text.length; i++) _style(r)];
  final lines = '\n'.allMatches(text).length + 1;
  return TextData.rich(
    text: text,
    spans: StyledRange.compact(chars),
    paras: [for (var i = 0; i < lines; i++) _para(r)],
    font: _box.font,
    fontSize: _box.fontSize,
  );
}

int _lines(String text) => '\n'.allMatches(text).length + 1;

int _lineOf(String text, int offset) => '\n'.allMatches(text.substring(0, offset)).length;

/// Checks [spans] are normalised over a text of [length] units.
void _expectNormalised(List<StyledRange> spans, int length) {
  var last = 0;
  StyledRange? previous;
  for (final s in spans) {
    expect(s.start, greaterThanOrEqualTo(last), reason: 'sorted, no overlap: $spans');
    expect(s.end, greaterThan(s.start), reason: 'non-empty: $s');
    expect(s.end, lessThanOrEqualTo(length), reason: 'within the text: $s');
    expect(s.style.isPlain, isFalse, reason: 'no plain span: $s');
    if (previous != null && previous.end == s.start) {
      expect(previous.style, isNot(s.style), reason: 'adjacent equal spans merged: $spans');
    }
    last = s.end;
    previous = s;
  }
}

/// The reference model: text, one style per unit, one paragraph per line.
class _Model {
  _Model(TextData d) : text = d.text, chars = d.charStyles(), paras = [...d.paras];

  String text;
  List<SpanStyle> chars;
  List<ParaStyle> paras;

  /// [RichTextBuffer.replace] as documented.
  void replace(int start, int end, String inserted, SpanStyle style) {
    final first = _lineOf(text, start), last = _lineOf(text, end);
    final added = '\n'.allMatches(inserted).length;
    final atLineStart = start == end && (start == 0 || text.codeUnitAt(start - 1) == 0x0A);
    final p = paras[first];
    final unchecked = p.copyWith(checked: false);
    final List<ParaStyle> middle;
    if (added == 0) {
      middle = [p];
    } else if (atLineStart) {
      middle = [for (var i = 0; i < added; i++) unchecked, p];
    } else {
      middle = [p, for (var i = 0; i < added; i++) ParaStyle(list: p.list, indent: p.indent)];
    }
    paras = [...paras.sublist(0, first), ...middle, ...paras.sublist(last + 1)];
    text = text.replaceRange(start, end, inserted);
    chars = [
      ...chars.sublist(0, start),
      for (var i = 0; i < inserted.length; i++) style,
      ...chars.sublist(end),
    ];
  }
}

void _expectMatches(RichTextBuffer buffer, _Model model) {
  expect(buffer.text, model.text);
  expect(buffer.lineCount, _lines(model.text), reason: 'one paragraph per line');
  expect([for (var i = 0; i < buffer.length; i++) buffer.charStyle(i)], model.chars);
  expect(buffer.paras, model.paras);
  // Its data is normalised, says the same and survives JSON and a new buffer.
  final data = buffer.toData(_box);
  _expectNormalised(data.spans, data.text.length);
  expect(data.charStyles(), model.chars);
  expect(data.paras, model.paras);
  final json = jsonDecode(jsonEncode(data.toJson())) as Map<String, Object?>;
  expect(TextData.fromJson(json), data, reason: 'JSON round trip');
  final again = RichTextBuffer(data);
  expect(again.text, buffer.text);
  expect(again.paras, buffer.paras);
}

/// A run of random edits on a buffer, checked against [_Model] after each.
void _edits(int seed) {
  final r = math.Random(seed);
  final initial = _data(r);
  final buffer = RichTextBuffer(initial);
  final model = _Model(initial);
  final log = <String>['start ${jsonEncode(initial.toJson())}'];
  try {
    for (var step = 0; step < 25; step++) {
      final a = r.nextInt(model.text.length + 1), b = r.nextInt(model.text.length + 1);
      final start = math.min(a, b), end = math.max(a, b);
      switch (r.nextInt(5)) {
        case 0 || 1:
          final inserted = _string(r, 6), style = _style(r);
          log.add('replace($start, $end, ${jsonEncode(inserted)}, $style)');
          buffer.replace(start, end, inserted, style);
          model.replace(start, end, inserted, style);
        case 2:
          final bold = r.nextBool(), colour = r.nextBool() ? _colour(r) : null;
          log.add('updateChars($start, $end, bold: $bold, colour: $colour)');
          SpanStyle update(SpanStyle s) => s.copyWith(bold: bold).withColor(colour);
          buffer.updateChars(start, end, update);
          for (var i = start; i < end; i++) {
            model.chars[i] = update(model.chars[i]);
          }
        case 3:
          final first = _lineOf(model.text, start), last = _lineOf(model.text, end);
          final p = _para(r);
          log.add('updateParas($first, $last, $p)');
          buffer.updateParas(first, last, (_) => p);
          model.paras.fillRange(first, last + 1, p);
        default:
          _pasteRich(r, buffer, model, start, end, log);
      }
      _expectMatches(buffer, model);
    }
  } on TestFailure catch (e) {
    fail('${log.join('\n')}\n$e');
  }
}

/// [RichTextBuffer.insertRich] of a random fragment: the text and the
/// pasted styles are exact; lines outside the paste keep their styles.
void _pasteRich(
  math.Random r,
  RichTextBuffer buffer,
  _Model model,
  int start,
  int end,
  List<String> log,
) {
  final fragment = _data(r, maxLength: 8);
  final base = _style(r);
  log.add('insertRich($start, $end, ${jsonEncode(fragment.toJson())}, $base)');
  final first = _lineOf(model.text, start), last = _lineOf(model.text, end);
  final before = model.paras.sublist(0, first), after = model.paras.sublist(last + 1);
  buffer.insertRich(start, end, fragment, base);
  model.replace(start, end, fragment.text, base);
  final styles = fragment.charStyles();
  for (var i = 0; i < styles.length; i++) {
    final s = styles[i];
    model.chars[start + i] = SpanStyle(
      bold: s.bold,
      italic: s.italic,
      underline: s.underline,
      strike: s.strike,
      color: s.color ?? base.color,
      highlight: s.highlight ?? base.highlight,
      size: s.size ?? base.size,
      font: s.font ?? base.font,
    );
  }
  final paras = buffer.paras;
  expect(paras.sublist(0, first), before, reason: 'lines above the paste');
  expect(paras.sublist(paras.length - after.length), after, reason: 'lines below the paste');
  // The paragraphs the paste spans are the fragment's (the first one's
  // depends on what it fills): take them from the buffer.
  model.paras = [...paras];
}

/// [data] as clipboard HTML in the style of a browser: one block per line,
/// list items carrying their level (Google Docs' `aria-level`), each run
/// of equal formatting in a styled `<span>` or plain tags.
String _html(TextData data, math.Random r) {
  final out = StringBuffer('<html><body><!--StartFragment-->');
  final chars = data.charStyles();
  var offset = 0;
  for (final (i, line) in data.text.split('\n').indexed) {
    final p = data.paras[i];
    final runs = StringBuffer();
    var j = 0;
    while (j < line.length) {
      final s = chars[offset + j];
      var k = j + 1;
      while (k < line.length && chars[offset + k] == s) {
        k++;
      }
      runs.write(_run(_escape(line.substring(j, k)), s, r));
      j = k;
    }
    offset += line.length + 1;
    final h = p.heading == 0 ? null : 'h${p.heading}';
    final body = h == null ? runs : '<$h>$runs</$h>';
    if (!p.isList) {
      out.write(h == null ? '<p>$body</p>' : body);
    } else {
      final tag = p.list == ListKind.number ? 'ol' : 'ul';
      final check = p.list == ListKind.check ? ' role="checkbox" aria-checked="${p.checked}"' : '';
      out.write('<$tag><li aria-level="${p.indent + 1}"$check>$body</li></$tag>');
    }
  }
  return '$out<!--EndFragment--></body></html>';
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

String _run(String text, SpanStyle s, math.Random r) {
  if (s.isPlain) return text;
  if (r.nextBool() && s.color == null && s.highlight == null && s.font == null) {
    // Plain tags.
    var t = text;
    if (s.bold) t = '<b>$t</b>';
    if (s.italic) t = '<em>$t</em>';
    if (s.underline) t = '<u>$t</u>';
    if (s.strike) t = '<s>$t</s>';
    return t;
  }
  final css = [
    if (s.bold) 'font-weight:700' else 'font-weight:normal',
    if (s.italic) 'font-style:italic',
    if (s.underline || s.strike)
      'text-decoration:${[if (s.underline) 'underline', if (s.strike) 'line-through'].join(' ')}',
    if (s.color != null) 'color:${_hex(s.color!)}',
    if (s.highlight != null) 'background-color:${_hex(s.highlight!)}',
    if (s.font == TextFont.mono) "font-family:'JetBrains Mono',monospace",
  ];
  return '<span style="${css.join(';')}">$text</span>';
}

/// Random text HTML can carry exactly: no empty lines, no space at either
/// end of a line or two in a row (browsers collapse them), sizes and
/// fonts other than mono left to the box.
TextData _htmlable(math.Random r) {
  const words = ['a', 'Bé', 'ß&', '<x>', '😀', 'z.', '"q"'];
  final lines = [
    for (var i = 1 + r.nextInt(4); i > 0; i--)
      [for (var w = 1 + r.nextInt(4); w > 0; w--) words[r.nextInt(words.length)]].join(' '),
  ];
  final text = lines.join('\n');
  final chars = [
    for (var i = 0; i < text.length; i++)
      text[i] == '\n' ? SpanStyle.plain : _style(r, sizes: false),
  ];
  // A space takes the style of the text it ends (as browsers render it).
  for (var i = 1; i < text.length; i++) {
    if (text[i] == ' ') chars[i] = chars[i - 1];
  }
  return TextData.rich(
    text: text,
    spans: StyledRange.compact(chars),
    paras: [for (final _ in lines) _para(r)],
    font: _box.font,
    fontSize: _box.fontSize,
  );
}

void main() {
  test('random edits keep text, styles and paragraphs as the reference model', () async {
    await forAll(Gens.intIn(0, 1 << 30), _edits, runs: 300, seed: 11);
  });

  test('normalising spans: any ranges give normalised spans with the same styles', () async {
    await forAll(
      (r) {
        final length = r.nextInt(20);
        return (
          length,
          [
            for (var i = r.nextInt(6); i > 0; i--)
              StyledRange(r.nextInt(length + 6) - 3, r.nextInt(length + 6) - 3, _style(r)),
          ],
        );
      },
      (c) {
        final (length, spans) = c;
        final normal = StyledRange.normalize(spans, length);
        _expectNormalised(normal, length);
        // Later spans win.
        final styles = List.filled(length, SpanStyle.plain);
        for (final s in spans) {
          final a = s.start.clamp(0, length), b = s.end.clamp(0, length);
          if (b > a) styles.fillRange(a, b, s.style);
        }
        final data = TextData.rich(text: 'x' * length, spans: normal);
        expect(data.charStyles(), styles);
        expect(StyledRange.normalize(normal, length), normal, reason: 'idempotent');
      },
      runs: 500,
      seed: 5,
    );
  });

  test('formatted text survives clipboard HTML', () async {
    await forAll(
      (r) => (_htmlable(r), r.nextInt(1 << 30)),
      (c) {
        final (data, seed) = c;
        final html = _html(data, math.Random(seed));
        final back = textFromHtml(html, _box);
        expect(back, isNotNull, reason: html);
        expect(back!.text, data.text, reason: html);
        expect(back.charStyles(), data.charStyles(), reason: html);
        expect(back.paras, data.paras, reason: html);
      },
      runs: 300,
      seed: 3,
      describe: (c) => _html(c.$1, math.Random(c.$2)),
    );
  });

  test('HTML parsing never throws on random markup', () async {
    const bits = [
      '<p>', '</p>', '<b>', '</b>', '<ul>', '<li>', '</li>', '</ul>', '<ol>', '<br>', '<pre>', //
      '</pre>', '&amp;', '&#x1F600;', '&#99999999;', '&bogus', '<', '>', '"', ' ', '\n', 'é',
      '<span style="color:rgb(1,2',
      '<!--',
      '-->',
      '<!--StartFragment-->',
      '<h1>',
      '<input type=checkbox checked>',
      '<li role="checkbox" aria-checked="true">', '<li aria-level="99">', 'Version:0.9', 'x',
    ];
    await forAll(
      (r) => [for (var i = r.nextInt(30); i > 0; i--) bits[r.nextInt(bits.length)]].join(),
      (html) {
        final d = textFromHtml(html, _box);
        if (d == null) return;
        _expectNormalised(d.spans, d.text.length);
        expect(d.paras, hasLength(_lines(d.text)));
        for (final p in d.paras) {
          expect(p.indent, inInclusiveRange(0, ParaStyle.maxIndent));
        }
      },
      runs: 1000,
      seed: 7,
    );
  });
}
