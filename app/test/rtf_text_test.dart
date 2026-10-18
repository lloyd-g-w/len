import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/rtf_text.dart';
import 'package:len/domain/text/rtf_tokens.dart';
import 'package:len/domain/text/text_data.dart';

const _box = TextData(fontSize: 20, font: TextFont.lora);

/// [body] in a minimal RTF document with a font and colour table.
String _doc(String body, {String header = ''}) =>
    r'{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss\fcharset0 Arial;}'
    r'{\f1\fmodern\fcharset0 Courier New;}{\f2\fnil\fcharset238 Arial;}'
    r'{\f3\fnil\fcharset204 Arial;}{\f4\fnil Consolas;}}'
    r'{\colortbl ;\red255\green0\blue0;\red128\green128\blue128;\red255\green255\blue0;}'
    '$header\\pard\\f0\\fs24 $body}';

TextData _parse(String body, {String header = ''}) =>
    textFromRtf(_doc(body, header: header), _box)!;

TextData _fixture(String name) {
  final bytes = File('test/fixtures/rtf/$name.rtf').readAsBytesSync();
  return textFromRtf(String.fromCharCodes(bytes), _box)!;
}

/// The style of the characters of [word] (its first occurrence).
SpanStyle _styleOf(TextData d, String word) {
  final i = d.text.indexOf(word);
  expect(i, isNonNegative, reason: '"$word" in "${d.text}"');
  final styles = d.charStyles().sublist(i, i + word.length).toSet();
  expect(styles, hasLength(1), reason: '"$word" has one style');
  return styles.single;
}

const _red = 0xFFFF0000, _yellow = 0xFFFFFF00;

void main() {
  group('textFromRtf: real-world samples', () {
    test('WordPad: formatting, sizes, code page 1250, pn bullets and numbers', () {
      final d = _fixture('wordpad');
      expect(d.text.split('\n'), [
        'Café notes: bold, italic, under and red text, marked and code().',
        'Big normal',
        'First item',
        'Second item',
        'One',
        'Two',
        'Příliš žluťoučký kůň',
      ]);
      expect(d.paras, const [
        ParaStyle.body,
        ParaStyle.body,
        ParaStyle(list: ListKind.bullet),
        ParaStyle(list: ListKind.bullet),
        ParaStyle(list: ListKind.number),
        ParaStyle(list: ListKind.number),
        ParaStyle.body,
      ]);
      expect(_styleOf(d, 'bold'), const SpanStyle(bold: true));
      expect(_styleOf(d, 'italic'), const SpanStyle(italic: true));
      expect(_styleOf(d, 'under'), const SpanStyle(underline: true));
      expect(_styleOf(d, 'red'), const SpanStyle(color: _red));
      expect(_styleOf(d, 'marked'), const SpanStyle(highlight: _yellow));
      expect(_styleOf(d, 'code()'), const SpanStyle(font: TextFont.mono));
      // 16 pt in an 11 pt body: 20 × 32 / 22.
      expect(_styleOf(d, 'Big'), const SpanStyle(size: 29));
      expect(_styleOf(d, 'normal'), SpanStyle.plain);
      // \sa200 (10 pt) after 11 pt paragraphs.
      expect(d.spacing, ParagraphSpacing.large);
      expect((d.font, d.fontSize), (TextFont.lora, 20.0));
    });

    test('Word: stylesheet headings, list table, \\u escapes, field results', () {
      final d = _fixture('word');
      expect(d.text.split('\n'), [
        'Meeting notes',
        'The plan is settled, the budget is not. Names: Příliš, Λόγος and 😀. See the site.',
        'Steps',
        'Book the room',
        'With a projector',
        'Coffee for everyone',
        'Decaf',
        'Remember the deadline.',
      ]);
      expect(d.paras, const [
        ParaStyle(heading: 1),
        ParaStyle.body,
        ParaStyle(heading: 2),
        ParaStyle(list: ListKind.number),
        ParaStyle(list: ListKind.number, indent: 1),
        ParaStyle(list: ListKind.bullet),
        ParaStyle(list: ListKind.bullet, indent: 1),
        ParaStyle.body,
      ]);
      expect(_styleOf(d, 'settled'), const SpanStyle(bold: true));
      expect(_styleOf(d, 'is not'), const SpanStyle(italic: true));
      expect(_styleOf(d, 'the site'), const SpanStyle(underline: true, color: 0xFF0563C1));
      expect(_styleOf(d, 'everyone'), const SpanStyle(font: TextFont.mono));
      expect(_styleOf(d, 'Decaf'), const SpanStyle(strike: true));
      expect(_styleOf(d, 'Remember'), const SpanStyle(highlight: _yellow));
      expect(_styleOf(d, 'deadline'), const SpanStyle(color: _red));
      // Headings keep their own (heading) size.
      expect(_styleOf(d, 'Meeting notes'), SpanStyle.plain);
      expect(d.spacing, ParagraphSpacing.medium);
    });

    test('TextEdit (Cocoa): bold / italic font faces, line ends, its list table', () {
      final d = _fixture('textedit');
      expect(d.text.split('\n'), [
        'Groceries',
        'Buy “fresh” things, ',
        'not frozen ones, ',
        'maybe tomorrow, use grep',
        'Apples',
        'Gala',
        'Pay',
        'Go home café',
      ]);
      expect(d.paras.sublist(4), const [
        ParaStyle(list: ListKind.bullet),
        ParaStyle(list: ListKind.bullet, indent: 1),
        ParaStyle(list: ListKind.number),
        ParaStyle(list: ListKind.number),
      ]);
      expect(_styleOf(d, 'Groceries'), const SpanStyle(bold: true, size: 30));
      expect(_styleOf(d, 'not'), const SpanStyle(bold: true));
      expect(_styleOf(d, 'frozen'), const SpanStyle(color: 0xFFFB0207));
      expect(_styleOf(d, 'maybe'), const SpanStyle(italic: true));
      expect(_styleOf(d, 'tomorrow'), const SpanStyle(highlight: 0xFFFFFB00));
      expect(_styleOf(d, 'grep'), const SpanStyle(font: TextFont.mono));
      expect(d.spacing, _box.spacing);
    });

    test('LibreOffice: heading, greys dropped, small print, Cyrillic, lists', () {
      final d = _fixture('libreoffice');
      expect(d.text.split('\n'), [
        'Report',
        'Normal text with bold, italic, underlined, struck and blue and highlighted and grey '
            'ignored. Small print and mono. Привет',
        'Bullet',
        'Nested',
        'Numbered',
      ]);
      expect(d.paras, const [
        ParaStyle(heading: 1),
        ParaStyle.body,
        ParaStyle(list: ListKind.bullet),
        ParaStyle(list: ListKind.bullet, indent: 1),
        ParaStyle(list: ListKind.number),
      ]);
      expect(_styleOf(d, 'Report'), const SpanStyle(bold: true));
      expect(_styleOf(d, 'underlined'), const SpanStyle(underline: true));
      expect(_styleOf(d, 'struck'), const SpanStyle(strike: true));
      expect(_styleOf(d, 'blue'), const SpanStyle(color: 0xFF0070C0));
      expect(_styleOf(d, 'highlighted'), const SpanStyle(highlight: _yellow));
      expect(_styleOf(d, 'ignored'), SpanStyle.plain);
      expect(_styleOf(d, 'Small print'), const SpanStyle(size: 13));
      expect(_styleOf(d, 'mono'), const SpanStyle(font: TextFont.mono));
      expect(d.spacing, ParagraphSpacing.medium);
    });
  });

  group('textFromRtf: control words', () {
    test('bold, italic, underline kinds, strike, \\plain and group restore', () {
      final d = _parse(
        r'a {\b b {\i bi} b} \ul u\ul0  \uldb d\ulnone  \ulw w\ul0  \strike s\strike0  '
        r'\striked1 x\striked0  \b\i\ul\cf1 all\plain  p',
      );
      expect(d.text, 'a b bi b u d w s x all p');
      expect(_styleOf(d, 'bi'), const SpanStyle(bold: true, italic: true));
      expect(d.charStyles()[2], const SpanStyle(bold: true));
      expect(d.charStyles()[7], const SpanStyle(bold: true));
      expect(_styleOf(d, 'u'), const SpanStyle(underline: true));
      expect(_styleOf(d, 'd'), const SpanStyle(underline: true));
      expect(_styleOf(d, 'w'), const SpanStyle(underline: true));
      expect(_styleOf(d, 's'), const SpanStyle(strike: true));
      expect(_styleOf(d, 'x'), const SpanStyle(strike: true));
      expect(
        _styleOf(d, 'all'),
        const SpanStyle(bold: true, italic: true, underline: true, color: _red),
      );
      expect(_styleOf(d, 'p'), SpanStyle.plain);
    });

    test('colours: greys and auto dropped; \\highlight, \\cb and \\chcbpat highlight', () {
      final d = _parse(
        r'\cf1 red\cf2  grey\cf0  auto \cf9 none \highlight3 hl\highlight0  '
        r'\cb3 cb\cb0  \chcbpat3 pat\chcbpat2  greyhl',
      );
      expect(_styleOf(d, 'red'), const SpanStyle(color: _red));
      expect(_styleOf(d, 'grey'), SpanStyle.plain);
      expect(_styleOf(d, 'auto'), SpanStyle.plain);
      expect(_styleOf(d, 'none'), SpanStyle.plain);
      for (final w in ['hl', 'cb', 'pat']) {
        expect(_styleOf(d, w), const SpanStyle(highlight: _yellow), reason: w);
      }
      expect(_styleOf(d, 'greyhl'), SpanStyle.plain);
    });

    test('monospaced fonts by family or name, not in a mono box', () {
      final d = _parse(r'{\f1 courier} {\f4 consolas} {\f0 arial}');
      expect(_styleOf(d, 'courier'), const SpanStyle(font: TextFont.mono));
      expect(_styleOf(d, 'consolas'), const SpanStyle(font: TextFont.mono));
      expect(_styleOf(d, 'arial'), SpanStyle.plain);
      final mono = textFromRtf(_doc(r'{\f1 courier}'), const TextData(font: TextFont.mono))!;
      expect(mono.spans, isEmpty);
    });

    test('font sizes relative to the body size; small differences ignored', () {
      final d = _parse(r'body text here {\fs48 big} {\fs26 near} {\fs12 small} {\fs2 tiny}');
      expect(_styleOf(d, 'body'), SpanStyle.plain);
      expect(_styleOf(d, 'big'), const SpanStyle(size: 40));
      expect(_styleOf(d, 'near'), SpanStyle.plain);
      expect(_styleOf(d, 'small'), const SpanStyle(size: 10));
      expect(_styleOf(d, 'tiny'), const SpanStyle(size: TextData.minFontSize));
    });

    test('line breaks: \\par, \\line, \\sect, \\page, \\row; \\tab and \\cell', () {
      final d = _parse(r'a\par b\line c\sect d\page e\cell f\row g\tab h');
      expect(d.text, 'a\nb\nc\nd\ne f\ng\th');
    });

    test('special characters', () {
      final d = _parse(
        r'a\~b\_c\-d \emdash \endash \bullet \lquote x\rquote  \ldblquote y\rdblquote  \{\}\\',
      );
      // (The space after a control word ends it.)
      expect(d.text, 'a b-cd —–•‘x’ “y” {}\\');
    });

    test('\\u: negative values, surrogate pairs, \\uc skip counts', () {
      expect(_parse(r'\u-3913 ?x').text, '\uF0B7x');
      expect(_parse(r'\u-10179?\u-8704?!').text, '😀!');
      expect(_parse(r'\uc0\u8226 x').text, '•x');
      expect(_parse(r'\uc2\u8226 ab x').text, '• x');
      expect(_parse(r"\u269\'e8 x").text, 'č x');
      // The skip count is the group's; a group end stops skipping.
      expect(_parse(r'{\uc2 \u269 ab}c {\u269}d').text, 'čc čd');
    });

    test("\\'hh by the font's charset or \\ansicpg", () {
      expect(_parse(r"caf\'e9 \'93q\'94 \'80").text, 'café “q” €');
      expect(_parse(r"\f2 \'9e\'e8\f0  \f3\'cf\'f0").text, 'žč Пр');
      final latin1 = textFromRtf(r"{\rtf1\ansi\ansicpg1253 \'e1}", _box)!;
      expect(latin1.text, '\u00E1');
    });

    test('hidden destinations and text are skipped; field results kept', () {
      final d = _parse(
        r'{\*\unknown x}{\info{\title T}}{\header H}{\footer F}{\*\themedata 504b}'
        r'{\pict\pngblip 89504e47}{\object{\*\objdata 01}}a{\footnote note}'
        r'{\field{\*\fldinst HYPERLINK "u"}{\fldrslt link}}{\v hidden}\bin3 {}xb',
      );
      expect(d.text, 'alinkb');
    });

    test('headings: \\outlinelevel and stylesheet names', () {
      final d = _parse(
        r'\outlinelevel0 One\par\pard\outlinelevel1 Two\par\pard\outlinelevel2 Three\par'
        r'\pard\outlinelevel3 Four\par\pard\s5 Five\par\pard\s6 Six\par\pard Body',
        header: r'{\stylesheet{Normal;}{\s5 heading 3;}{\s6\outlinelevel0 Title;}}',
      );
      expect([for (final p in d.paras) p.heading], [1, 2, 2, 0, 2, 1, 0]);
    });

    test('list markers decide bullets and numbers without a list table', () {
      final d = _parse(
        r"{\listtext 1.\tab}\ls1 one\par{\listtext a)\tab}\ls1\ilvl1 two\par"
        r"\pard{\listtext\f0 \'95\tab}\ls2 three\par\pard{\pntext\f0 (iv)\tab}four\par"
        r'\pard\ls3\ilvl9 deep\par\pard plain',
      );
      expect(d.paras, const [
        ParaStyle(list: ListKind.number),
        ParaStyle(list: ListKind.number, indent: 1),
        ParaStyle(list: ListKind.bullet),
        ParaStyle(list: ListKind.number),
        ParaStyle(list: ListKind.bullet, indent: ParaStyle.maxIndent),
        ParaStyle.body,
      ]);
      expect(d.text, 'one\ntwo\nthree\nfour\ndeep\nplain');
    });

    test('the list table wins over markers; \\levelnfc255 is no list', () {
      final d = _parse(
        r'{\listtext 1.\tab}\ls1 bullet\par\pard\ls1\ilvl1 number\par\pard\ls2 none',
        header:
            r'{\*\listtable{\list{\listlevel\levelnfc23}{\listlevel\levelnfc4}\listid7}'
            r'{\list{\listlevel\levelnfc255}\listid8}}'
            r'{\*\listoverridetable{\listoverride\listid7\ls1}{\listoverride\listid8\ls2}}',
      );
      expect(d.paras, const [
        ParaStyle(list: ListKind.bullet),
        ParaStyle(list: ListKind.number, indent: 1),
        ParaStyle.body,
      ]);
    });

    test('\\pn numbering: bullets, numbers, levels', () {
      final d = _parse(
        r'{\*\pn\pnlvlblt{\pntxtb\bullet}}a\par\pard{\*\pn\pnlvlbody\pndec}b\par'
        r'\pard{\*\pn\pnlvl2\pnlcltr}c\par\pard d',
      );
      expect(d.paras, const [
        ParaStyle(list: ListKind.bullet),
        ParaStyle(list: ListKind.number),
        ParaStyle(list: ListKind.number, indent: 1),
        ParaStyle.body,
      ]);
    });

    test('paragraph spacing from \\sa / \\sb relative to the body size', () {
      expect(_parse(r'\sa0 a\par b').spacing, ParagraphSpacing.none);
      expect(_parse(r'\sa60 a\par b').spacing, ParagraphSpacing.small);
      expect(_parse(r'\sb120 a\par b').spacing, ParagraphSpacing.medium);
      expect(_parse(r'\sa240 a\par b').spacing, ParagraphSpacing.large);
      const spaced = TextData(spacing: ParagraphSpacing.small);
      expect(textFromRtf(_doc('a'), spaced)!.spacing, ParagraphSpacing.small);
    });

    test('blank lines at either end are trimmed; inner ones kept', () {
      expect(_parse(r'\par\par a\par\par b\par\par ').text, 'a\n\nb');
    });
  });

  group('textFromRtf: input', () {
    test('a byte order mark, trailing NULs and CR LF line ends are accepted', () {
      expect(textFromRtf('\uFEFF{\\rtf1 a\r\nb}\x00\x00', _box)!.text, 'ab');
    });

    test('no text, not RTF or garbage: null', () {
      expect(textFromRtf('', _box), isNull);
      expect(textFromRtf('hello', _box), isNull);
      expect(textFromRtf('<b>html</b>', _box), isNull);
      expect(textFromRtf(r'{\rtf1{\fonttbl{\f0 Arial;}}\par\par }', _box), isNull);
      expect(textFromRtf(r'{\rtf1 \', _box), isNull);
      expect(textFromRtf(r'{\rtf1 }}}}{{{\x', _box), isNull);
      expect(textFromRtf(r"{\rtf1 a}}} b\'zz{", _box)!.text, 'a bzz');
    });

    test('tokens: words with params, symbols, bytes, \\bin data', () {
      final tokens = tokenizeRtf(r"{\b0\fs-12 x\'e9\~\bin2 {}y}").toList();
      expect(tokens.map((t) => t.toString()).length, 8);
      expect((tokens[1] as RtfWord).param, 0);
      expect((tokens[2] as RtfWord).param, -12);
      expect((tokens[3] as RtfText).text, 'x');
      expect((tokens[4] as RtfByte).value, 0xE9);
      expect((tokens[5] as RtfWord).name, '~');
      expect((tokens[6] as RtfText).text, 'y');
    });
  });
}
