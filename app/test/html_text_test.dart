import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/html_css.dart';
import 'package:len/domain/text/html_text.dart';
import 'package:len/domain/text/rich_text_buffer.dart';
import 'package:len/domain/text/text_data.dart';

const _box = TextData(fontSize: 20, font: TextFont.lora);

TextData _parse(String html) => textFromHtml(html, _box)!;

/// The styles of the characters of [word] (its first occurrence).
SpanStyle _styleOf(TextData d, String word) {
  final i = d.text.indexOf(word);
  expect(i, isNonNegative, reason: '"$word" in "${d.text}"');
  final styles = d.charStyles().sublist(i, i + word.length).toSet();
  expect(styles, hasLength(1), reason: '"$word" has one style');
  return styles.single;
}

void main() {
  group('textFromHtml', () {
    test('inline formatting from tags and styles', () {
      final d = _parse(
        '<p>a <b>bold</b> <strong>strong</strong> <i>it</i> <em>em</em> <u>under</u> '
        '<s>gone</s> <del>del</del> <span style="font-weight:700">heavy</span> '
        '<span style="font-style: italic; text-decoration: underline line-through">mix</span></p>',
      );
      expect(d.text, 'a bold strong it em under gone del heavy mix');
      expect(_styleOf(d, 'bold').bold, isTrue);
      expect(_styleOf(d, 'strong').bold, isTrue);
      expect(_styleOf(d, 'it').italic, isTrue);
      expect(_styleOf(d, 'em').italic, isTrue);
      expect(_styleOf(d, 'under').underline, isTrue);
      expect(_styleOf(d, 'gone').strike, isTrue);
      expect(_styleOf(d, 'del').strike, isTrue);
      expect(_styleOf(d, 'heavy').bold, isTrue);
      expect(_styleOf(d, 'mix'), const SpanStyle(italic: true, underline: true, strike: true));
      expect(_styleOf(d, 'a '), SpanStyle.plain);
      // The box keeps its defaults.
      expect(d.font, TextFont.lora);
      expect(d.fontSize, 20);
    });

    test('entities and browser whitespace', () {
      final d = _parse(
        '<div>\n  Fish &amp; chips&nbsp;&nbsp;x &lt;3 &#233;t&#xE9; &#x1F600; &bogus;\n'
        '   <b> spaced </b>  out </div>',
      );
      expect(d.text, 'Fish & chips  x <3 été 😀 &bogus; spaced out');
      expect(d.spans.single.style.bold, isTrue);
    });

    test('paragraphs, divs and line breaks', () {
      final d = _parse('<p>one</p><p>two<br>three</p><br><div>four</div>\n<p>five<br></p>');
      expect(d.text, 'one\ntwo\nthree\n\nfour\nfive');
    });

    test('ignores head, style and script', () {
      final d = _parse(
        '<html><head><title>T</title><style>p{color:red}</style></head>'
        '<body><script>alert(1)</script><p>only</p></body></html>',
      );
      expect(d.text, 'only');
    });

    test('headings', () {
      final d = _parse('<h1>Title</h1><h2>Sub</h2><h3>Third</h3><h4>Four</h4><p>body</p>');
      expect(d.text, 'Title\nSub\nThird\nFour\nbody');
      expect([for (final p in d.paras) p.heading], [1, 2, 2, 0, 0]);
      expect(_styleOf(d, 'Four').bold, isTrue);
    });

    test('nested lists', () {
      final d = _parse(
        '<ul><li>a<ul><li>a1</li><li>a2<ol><li>deep</li></ol></li></ul></li>'
        '<li>b</li></ul><ol><li>one<li>two</ol><p>after</p>',
      );
      expect(d.text, 'a\na1\na2\ndeep\nb\none\ntwo\nafter');
      expect(
        [for (final p in d.paras) (p.list, p.indent)],
        [
          (ListKind.bullet, 0),
          (ListKind.bullet, 1),
          (ListKind.bullet, 1),
          (ListKind.number, 2),
          (ListKind.bullet, 0),
          (ListKind.number, 0),
          (ListKind.number, 0),
          (ListKind.none, 0),
        ],
      );
    });

    test('checklists from checkbox inputs and ARIA', () {
      final d = _parse(
        '<ul><li><input type="checkbox" checked> done</li>'
        '<li><input type="checkbox"> todo</li>'
        '<li role="checkbox" aria-checked="true">aria</li></ul>',
      );
      expect(d.text, 'done\ntodo\naria');
      expect(
        [for (final p in d.paras) (p.list, p.checked)],
        [(ListKind.check, true), (ListKind.check, false), (ListKind.check, true)],
      );
    });

    test('decoration hidden from screen readers is skipped; empty items stay items', () {
      final d = _parse(
        '<ul><li role="checkbox" aria-checked="false"><span aria-hidden="true">☐ <br></span>'
        'todo</li><li><br></li></ul><h1><br></h1><p>end</p>',
      );
      expect(d.text, 'todo\n\n\nend');
      expect(d.paras, const [
        ParaStyle(list: ListKind.check),
        ParaStyle(list: ListKind.bullet),
        ParaStyle(heading: 1),
        ParaStyle.body,
      ]);
    });

    test('Google Docs: wrapping non-bold <b>, styled spans, flat nested lists', () {
      const html =
          '<meta charset="utf-8"><b style="font-weight:normal;" id="docs-internal-guid-1a2b">'
          '<h1 dir="ltr" style="line-height:1.38;margin-top:20pt"><span style="font-size:20pt;'
          'font-family:Arial,sans-serif;color:#000000;font-weight:400">Plan</span></h1>'
          '<p dir="ltr"><span style="font-size:11pt;color:#000000;background-color:transparent;'
          'font-weight:400;font-style:normal">Some </span><span style="font-size:11pt;'
          'color:#000000;font-weight:700">bold</span><span style="font-weight:400"> and </span>'
          '<span style="font-weight:400;font-style:italic;color:#ff0000">red italic</span></p>'
          '<ul style="margin-top:0;margin-bottom:0"><li dir="ltr" aria-level="1" '
          'style="list-style-type:disc"><p dir="ltr" role="presentation"><span>Top</span></p></li>'
          '<li dir="ltr" aria-level="2" style="list-style-type:circle"><p dir="ltr" '
          'role="presentation"><span>Nested</span></p></li></ul>'
          '<br><p dir="ltr"><span style="background-color:#ffff00;font-weight:400">marked</span></p>'
          '</b>';
      final d = _parse(html);
      expect(d.text, 'Plan\nSome bold and red italic\nTop\nNested\n\nmarked');
      expect(d.paras[0].heading, 1);
      expect(_styleOf(d, 'Some'), SpanStyle.plain);
      expect(_styleOf(d, 'bold'), const SpanStyle(bold: true));
      expect(_styleOf(d, 'red italic'), const SpanStyle(italic: true, color: 0xFFFF0000));
      expect((d.paras[2].list, d.paras[2].indent), (ListKind.bullet, 0));
      expect((d.paras[3].list, d.paras[3].indent), (ListKind.bullet, 1));
      expect(_styleOf(d, 'marked').highlight, 0xFFFFFF00);
    });

    test('Word via CF_HTML: header, fragment markers, list paragraphs', () {
      const fragment =
          '<p class=MsoNormal><b><span lang=EN-GB>Heading-ish</span></b><o:p></o:p></p>\r\n'
          "<p class=MsoListParagraphCxSpFirst style='text-indent:-18.0pt;mso-list:l0 level1 lfo1'>"
          "<![if !supportLists]><span style='font-family:Symbol'>·<span "
          'style=\'font:7.0pt "Times New Roman"\'>&nbsp;&nbsp;&nbsp; </span></span><![endif]>'
          '<span lang=EN-GB>First</span></p>\r\n'
          "<p class=MsoListParagraphCxSpLast style='mso-list:l0 level2 lfo1'>"
          '<![if !supportLists]><span>a.<span>&nbsp;&nbsp; </span></span><![endif]>'
          '<i>Second</i></p>\r\n';
      const html =
          'Version:0.9\r\nStartHTML:0000000105\r\nEndHTML:0000000999\r\n'
          'StartFragment:0000000200\r\nEndFragment:0000000900\r\n'
          '<html xmlns:o="urn:schemas-microsoft-com:office:office"><head>'
          '<style><!-- p.MsoNormal {margin:0} --></style><xml><o:shapedefaults/></xml></head>'
          '<body lang=EN-GB><!--StartFragment-->$fragment<!--EndFragment--></body></html>';
      final d = _parse(html);
      expect(d.text, 'Heading-ish\nFirst\nSecond');
      expect(_styleOf(d, 'Heading-ish').bold, isTrue);
      expect((d.paras[1].list, d.paras[1].indent), (ListKind.bullet, 0));
      expect((d.paras[2].list, d.paras[2].indent), (ListKind.number, 1));
      expect(_styleOf(d, 'Second').italic, isTrue);
    });

    test('browser selection (Chrome, inlined computed styles)', () {
      const html =
          '<meta charset=\'utf-8\'><h2 style="color: rgb(32, 33, 36); font-family: Roboto;">'
          'Install</h2><p style="color: rgb(32, 33, 36); background-color: rgb(255, 255, 255);">'
          'Run <code style="font-family: monospace;">make</code> then '
          '<a href="https://x.test">read <em>the docs</em></a>.</p><pre>line 1\n  line 2</pre>';
      final d = _parse(html);
      expect(d.text, 'Install\nRun make then read the docs.\nline 1\n  line 2');
      expect(d.paras[0].heading, 2);
      expect(_styleOf(d, 'Run '), SpanStyle.plain);
      expect(_styleOf(d, 'make').font, TextFont.mono);
      expect(_styleOf(d, 'the docs').italic, isTrue);
      expect(_styleOf(d, '  line 2').font, TextFont.mono);
    });

    test('nothing but markup is null; tolerates broken markup', () {
      expect(textFromHtml('<p> </p><br>', _box), isNull);
      expect(textFromHtml('', _box), isNull);
      expect(_parse('a < b <b>bold <i>both</b> x').text, 'a < b bold both x');
      expect(_parse('<p title="a>b">quoted</p>').text, 'quoted');
    });
  });

  test('a stray <li> is a top-level item; deep nesting stops at the deepest indent', () {
    final d = _parse(
      '<li>stray</li><ul><ul><ul><ul><ul><ul><li>deep</li></ul></ul></ul></ul></ul></ul>',
    );
    expect(d.paras, [
      const ParaStyle(list: ListKind.bullet),
      const ParaStyle(list: ListKind.bullet, indent: ParaStyle.maxIndent),
    ]);
    expect(TextData.fromJson(d.toJson()), d, reason: 'indents survive JSON');
  });

  test('parseColor', () {
    expect(parseColor('#f00'), 0xFFFF0000);
    expect(parseColor('#1a73e8'), 0xFF1A73E8);
    expect(parseColor('rgb(26, 115, 232)'), 0xFF1A73E8);
    expect(parseColor('rgba(26, 115, 232, 0)'), isNull);
    expect(parseColor('#000000'), isNull);
    expect(parseColor('rgb(255,255,255)'), isNull);
    expect(parseColor('transparent'), isNull);
    expect(parseColor('red'), 0xFFFF0000);
    // Unclosed (cut-off markup) is read, not a RangeError.
    expect(parseColor('rgb(26, 115, 232'), 0xFF1A73E8);
    expect(parseColor('rgb(1,2'), isNull);
  });

  group('RichTextBuffer.insertRich', () {
    const caret = SpanStyle(size: 30, color: 0xFF0000FF);
    final item = TextData.rich(
      text: 'item',
      paras: const [ParaStyle(list: ListKind.bullet)],
      spans: const [StyledRange(0, 4, caret)],
    );

    test('one formatted line pasted into a list item keeps the item', () {
      final b = RichTextBuffer(item)..insertRich(4, 4, _parse('<p>, and <b>more</b></p>'), caret);
      final d = b.toData(_box);
      expect(d.text, 'item, and more');
      expect(d.paras, const [ParaStyle(list: ListKind.bullet)]);
      expect(d.charStyles()[11], const SpanStyle(bold: true, size: 30, color: 0xFF0000FF));
    });

    test('lines take the fragment paragraph styles; a filled line too', () {
      final b = RichTextBuffer(item)
        ..insertRich(0, 4, _parse('<h1>T</h1><ol><li>x</li></ol>'), caret);
      expect(b.toData(_box).paras, const [ParaStyle(heading: 1), ParaStyle(list: ListKind.number)]);
    });

    test('lines pasted at the start of a line go above it; the line keeps its style', () {
      final title = TextData.rich(text: 'Title', paras: const [ParaStyle(heading: 1)]);
      final b = RichTextBuffer(title)..insertRich(0, 0, _parse('<h2>A</h2><p>B</p>'), caret);
      final d = b.toData(_box);
      expect(d.text, 'A\nBTitle');
      expect(d.paras, const [ParaStyle(heading: 2), ParaStyle(heading: 1)]);

      final list = RichTextBuffer(item)..insertRich(0, 0, _parse('<p>A</p><p>B</p>'), caret);
      expect(list.toData(_box).paras, const [
        ParaStyle(list: ListKind.bullet),
        ParaStyle(list: ListKind.bullet),
      ]);
    });
  });

  test('a fragment marker cut short reads the whole document', () {
    expect(fragmentOf('<p>a</p><!--StartFragment'), '<p>a</p><!--StartFragment');
    expect(_parse('<p>hello</p><!--StartFragment').text, 'hello');
  });
}
