import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/html_text.dart';
import 'package:len/domain/text/html_writer.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/tools/text/text_style_menus.dart' show textHighlights;
import 'package:pasteboard/pasteboard.dart';

import 'support/property.dart';

/// Rich copy to other apps (UX_AUDIT round 19): formatted text as HTML,
/// read back the same by `textFromHtml`.

const _box = TextData();

TextData _read(String html, [TextData box = _box]) => textFromHtml(html, box)!;

void main() {
  group('htmlFromText', () {
    test('inline formatting as tags, colours and fonts as styles', () {
      final data = TextData.rich(
        text: 'a bold red mark code',
        spans: const [
          StyledRange(2, 6, SpanStyle(bold: true, italic: true, underline: true, strike: true)),
          StyledRange(7, 10, SpanStyle(color: 0xFFE53935)),
          StyledRange(11, 15, SpanStyle(highlight: 0x80FFEB3B)),
          StyledRange(16, 20, SpanStyle(font: TextFont.mono)),
        ],
      );
      expect(
        htmlFromText(data),
        '<div>a <b><i><u><s>bold</s></u></i></b> <span style="color:#e53935">red</span> '
        '<span style="background-color:#fff59d">mark</span> '
        '<span style="font-family:\'JetBrains Mono\',Consolas,\'Courier New\',monospace">'
        'code</span></div>',
      );
    });

    test('headings, nested lists and checklists', () {
      final data = TextData.rich(
        text: 'Title\none\ninner\ntwo\ntodo\ndone\nend',
        paras: const [
          ParaStyle(heading: 1),
          ParaStyle(list: ListKind.number),
          ParaStyle(list: ListKind.bullet, indent: 1),
          ParaStyle(list: ListKind.number),
          ParaStyle(list: ListKind.check),
          ParaStyle(list: ListKind.check, checked: true),
          ParaStyle.body,
        ],
      );
      expect(
        htmlFromText(data),
        '<h1>Title</h1>'
        '<ol><li>one<ul><li>inner</li></ul></li><li>two</li></ol>'
        '<ul style="list-style-type:none">'
        '<li role="checkbox" aria-checked="false"><span aria-hidden="true">☐ </span>todo</li>'
        '<li role="checkbox" aria-checked="true"><span aria-hidden="true">☑ </span>done</li>'
        '</ul><div>end</div>',
      );
      final back = _read(htmlFromText(data));
      expect(back.text, data.text);
      expect(back.paras, data.paras);
    });

    test('spaces HTML would collapse, tabs, empty lines and markup characters', () {
      final data = TextData.rich(text: ' a  b\t<c> & d \n\nx', paras: const []);
      final html = htmlFromText(data);
      expect(
        html,
        '<div>&nbsp;a &nbsp;b<span style="white-space:pre">\t</span>&lt;c&gt; &amp; d&nbsp;</div>'
        '<div><br></div><div>x</div>',
      );
      expect(_read(html).text, data.text);
    });

    test('black and grey text, Inter and start alignment add nothing', () {
      expect(htmlFromText(const TextData(text: 'plain')), '<div>plain</div>');
      expect(
        htmlFromText(const TextData(text: 'x', color: 0xFF2E7D32, align: TextAlignment.center)),
        '<div style="text-align:center"><span style="color:#2e7d32">x</span></div>',
      );
    });

    test('right-to-left paragraphs say so; end alignment is physical', () {
      expect(
        htmlFromText(const TextData(text: 'שלום\nhi')),
        '<div dir="rtl">שלום</div><div>hi</div>',
      );
      expect(
        htmlFromText(const TextData(text: 'שלום\nhi', align: TextAlignment.end)),
        '<div dir="rtl" style="text-align:left">שלום</div><div style="text-align:right">hi</div>',
      );
    });

    test('several boxes: an empty line between', () {
      final html = htmlFromTexts(const [TextData(text: 'a'), TextData(text: 'b')]);
      expect(_read(html).text, 'a\n\nb');
    });

    test('boxes ending in blank lines end at their text, as the plain text does', () {
      final html = htmlFromTexts([
        const TextData(text: 'a\n\n'),
        TextData.rich(
          text: 'b  \n \n',
          paras: const [
            ParaStyle.body,
            ParaStyle(list: ListKind.bullet),
            ParaStyle.body,
          ],
        ),
      ]);
      expect(html, htmlFromTexts(const [TextData(text: 'a'), TextData(text: 'b')]));
      expect(_read(html).text, 'a\n\nb');
      // One box copied in its own field keeps what was selected.
      expect(_read(htmlFromText(const TextData(text: 'a\n\nb'))).text, 'a\n\nb');
    });

    test("Len's highlights stay colours once blended onto white", () {
      for (final h in textHighlights) {
        expect(htmlHighlight(h), isNotNull, reason: h.toRadixString(16));
      }
      expect(htmlHighlight(0x00FFEB3B), isNull);
      expect(htmlTextColor(TextData.defaultColor), isNull);
    });
  });

  test('formatted text survives HTML written for other apps', () async {
    await forAll(
      _anyText,
      (data) {
        final html = htmlFromText(data);
        final back = textFromHtml(html, data);
        final want = _readable(data);
        if (want == null) {
          expect(back, isNull, reason: html);
          return;
        }
        expect(back, isNotNull, reason: html);
        expect(back!.text, want.text, reason: html);
        expect(back.charStyles(), want.charStyles(), reason: html);
        expect(back.paras, want.paras, reason: html);
      },
      runs: 500,
      seed: 19,
      describe: (d) => '${jsonEncode(d.toJson())}\n${htmlFromText(d)}',
    );
  });

  group('CF_HTML', () {
    test('the header gives the UTF-8 byte offsets of the document and fragment', () {
      const fragment = '<b>é 😀</b>';
      final cf = encodeCfHtml(fragment);
      final bytes = utf8.encode(cf);
      int offset(String name) => int.parse(RegExp('$name:(\\d+)').firstMatch(cf)!.group(1)!);
      String at(int from, int to) => utf8.decode(bytes.sublist(from, to));
      expect(at(offset('StartFragment'), offset('EndFragment')), fragment);
      expect(at(offset('StartHTML'), offset('StartHTML') + 6), '<html>');
      expect(offset('EndHTML'), bytes.length);
      expect(cf, startsWith('Version:0.9\r\n'));
      // Len reads it back.
      expect(_read(cf).text, 'é 😀');
    });
  });
}

/// What `textFromHtml` can give back of [data] written as HTML: sizes and
/// fonts other than mono are the box's, colours are opaque and not grey,
/// highlights blended onto white, blank lines at either end dropped.
TextData? _readable(TextData data) {
  final styles = data.charStyles();
  final lines = data.text.split('\n');
  var first = 0, last = lines.length - 1;
  while (first <= last && lines[first].trim().isEmpty) {
    first++;
  }
  while (last >= first && lines[last].trim().isEmpty) {
    last--;
  }
  if (first > last) return null;
  final start = lines.take(first).fold(0, (n, l) => n + l.length + 1);
  final text = lines.sublist(first, last + 1).join('\n');
  final chars = [
    for (var i = 0; i < text.length; i++)
      text[i] == '\n' ? SpanStyle.plain : _readableStyle(styles[start + i], data),
  ];
  return TextData.rich(
    text: text,
    spans: StyledRange.compact(chars),
    paras: data.paras.sublist(first, last + 1),
  );
}

SpanStyle _readableStyle(SpanStyle s, TextData box) => SpanStyle(
  bold: s.bold,
  italic: s.italic,
  underline: s.underline,
  strike: s.strike,
  color: htmlTextColor(s.color ?? box.color),
  highlight: s.highlight == null ? null : htmlHighlight(s.highlight!),
  font: (s.font ?? box.font) == TextFont.mono && box.font != TextFont.mono ? TextFont.mono : null,
);

const _colors = [0xFF1A2233, 0xFF000000, 0xFF808080, 0xFFE53935, 0xFF1E88E5, 0x80FF0000, 0];

/// Any formatted text a box may hold (but characters HTML drops: zero
/// widths, carriage returns, no-break spaces).
TextData _anyText(math.Random r) {
  const pieces = [
    'a', 'Bé', ' ', '  ', '\t', '&', '<x>', '😀', 'z.', '"q"', '\n', '\n\n', ' \n', //
  ];
  final text = [for (var i = r.nextInt(14); i > 0; i--) pieces[r.nextInt(pieces.length)]].join();
  final chars = [for (var i = 0; i < text.length; i++) _style(r)];
  // Runs, so styles change at word boundaries too, not only every unit.
  for (var i = 1; i < text.length; i++) {
    if (r.nextDouble() < 0.6) chars[i] = chars[i - 1];
  }
  final lines = '\n'.allMatches(text).length + 1;
  return TextData.rich(
    text: text,
    spans: StyledRange.compact(chars),
    paras: [for (var i = 0; i < lines; i++) _para(r)],
    font: TextFont.values[r.nextInt(TextFont.values.length)],
    color: _colors[r.nextInt(_colors.length)],
    align: TextAlignment.values[r.nextInt(TextAlignment.values.length)],
  );
}

SpanStyle _style(math.Random r) {
  if (r.nextDouble() < 0.4) return SpanStyle.plain;
  return SpanStyle(
    bold: r.nextBool(),
    italic: r.nextBool(),
    underline: r.nextDouble() < 0.3,
    strike: r.nextDouble() < 0.3,
    color: r.nextDouble() < 0.4 ? _colors[r.nextInt(_colors.length)] : null,
    highlight: r.nextDouble() < 0.3 ? textHighlights[r.nextInt(textHighlights.length)] : null,
    size: r.nextDouble() < 0.2 ? 30 : null,
    font: r.nextDouble() < 0.3 ? TextFont.values[r.nextInt(TextFont.values.length)] : null,
  );
}

ParaStyle _para(math.Random r) {
  if (r.nextDouble() < 0.3) return ParaStyle.body;
  final list = ListKind.values[r.nextInt(ListKind.values.length)];
  return ParaStyle(
    heading: r.nextDouble() < 0.2 ? 1 + r.nextInt(2) : 0,
    list: list,
    checked: list == ListKind.check && r.nextBool(),
    indent: list == ListKind.none ? 0 : r.nextInt(ParaStyle.maxIndent + 1),
  );
}
