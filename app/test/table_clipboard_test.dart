import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/html_text.dart';
import 'package:len/domain/text/html_writer.dart';
import 'package:len/domain/text/rich_text_buffer.dart';
import 'package:len/domain/text/rtf_text.dart';
import 'package:len/domain/text/table_edits.dart';
import 'package:len/domain/text/text_data.dart';

/// Tables on the clipboard: written as HTML, read from HTML (browsers,
/// Word, LibreOffice, Google Docs) and RTF (Word, LibreOffice).

const _box = TextData();

/// "Intro", a [rows] × [cells.length / rows] table of [cells], "End".
TextData _table(List<String> cells, int rows, {bool header = false, List<double>? widths}) {
  final b = RichTextBuffer(const TextData(text: 'Intro\n'));
  final t = b.insertTable(6, rows, cells.length ~/ rows, header: header);
  if (widths != null) b.setSpec(t, t.spec.copyWith(widths: widths));
  for (final (k, c) in cells.indexed) {
    b.setCell(t.line + k, c, List.filled(c.length, SpanStyle.plain));
  }
  b.replace(b.length, b.length, 'End', SpanStyle.plain);
  return b.toData(const TextData());
}

/// The cell texts of [d]'s only table, and the lines around it.
List<String> _cells(TextData d) {
  final t = TextTables.of(d.paras).single;
  return d.text.split('\n').sublist(t.line, t.end);
}

TextTable _only(TextData d) => TextTables.of(d.paras).single;

SpanStyle _styleOf(TextData d, String word) => d.charStyles()[d.text.indexOf(word)];

void main() {
  group('htmlFromText', () {
    test('a table as bordered cells, header row as <th>, widths in percent', () {
      final d = _table(['a', 'b', 'c', ''], 2, header: true, widths: [0.25, 0.75]);
      const cell = 'border:1px solid #ccc;padding:2px 6px';
      expect(
        htmlFromText(d),
        '<div>Intro</div>'
        '<table style="border-collapse:collapse">'
        '<tr><th style="$cell;width:25.0%">a</th><th style="$cell;width:75.0%">b</th></tr>'
        '<tr><td style="$cell;width:25.0%">c</td><td style="$cell;width:75.0%"><br></td></tr>'
        '</table><div>End</div>',
      );
    });

    test('a right-to-left box writes its table right to left, as it lays it out', () {
      final b = RichTextBuffer(const TextData(text: 'שלום'));
      final t = b.insertTable(4, 1, 2);
      b.setCell(t.line, 'אב', List.filled(2, SpanStyle.plain));
      expect(htmlFromText(b.toData(const TextData())), contains('<table dir="rtl" style='));
      expect(htmlFromText(_table(['a', 'b'], 1)), isNot(contains('dir="rtl"')));
    });

    test('cells keep inline formatting; lists close before a table', () {
      final b = RichTextBuffer(const TextData(text: 'item\n'));
      b.updateParas(0, 0, (_) => const ParaStyle(list: ListKind.bullet));
      final t = b.insertTable(5, 1, 2);
      b.setCell(t.line, 'bold', List.filled(4, const SpanStyle(bold: true)));
      b.setCell(t.line + 1, 'red', List.filled(3, const SpanStyle(color: 0xFFE53935)));
      final html = htmlFromText(b.toData(const TextData()));
      expect(html, startsWith('<ul><li>item</li></ul><table'));
      expect(html, contains('<b>bold</b></td>'));
      expect(html, contains('<span style="color:#e53935">red</span></td>'));
    });

    test('a box ending in a table keeps its empty last row', () {
      final b = RichTextBuffer(const TextData());
      final t = b.insertTable(0, 2, 2);
      b.setCell(t.line, 'x', const [SpanStyle.plain]);
      final html = htmlFromTexts([b.toData(const TextData())]);
      expect('<tr>'.allMatches(html).length, 2);
      expect('<td'.allMatches(html).length, 4);
    });
  });

  group('round trip', () {
    test('cells, columns, header, formatting and widths come back', () {
      final b = RichTextBuffer(const TextData(text: 'Before\n'));
      final t = b.insertTable(7, 2, 3, header: true);
      b.setSpec(t, t.spec.copyWith(widths: [0.2, 0.5, 0.3]));
      final texts = ['Name', 'Qty', 'Note', 'apple', '3', 'very red'];
      for (final (k, c) in texts.indexed) {
        b.setCell(t.line + k, c, List.filled(c.length, SpanStyle.plain));
      }
      b.setCell(t.line + 5, 'very red', [
        ...List.filled(5, const SpanStyle(italic: true)),
        ...List.filled(3, const SpanStyle(color: 0xFFE53935, underline: true)),
      ]);
      final data = b.toData(const TextData());
      final back = textFromHtml(htmlFromText(data), _box)!;
      expect(back.text, data.text);
      expect(back.charStyles(), data.charStyles());
      final spec = _only(back).spec;
      expect(spec.columns, 3);
      expect(spec.header, isTrue);
      for (var c = 0; c < 3; c++) {
        expect(spec.widths[c], closeTo(_only(data).spec.widths[c], 0.01));
      }
      expect(back.paras, data.paras);
    });

    test('a table ending the text comes back with a line after it', () {
      final b = RichTextBuffer(const TextData());
      final t = b.insertTable(0, 1, 2);
      b.setCell(t.line, 'a', const [SpanStyle.plain]);
      final data = b.toData(const TextData());
      final back = textFromHtml(htmlFromText(data), _box)!;
      expect(back.text, 'a\n\n');
      expect(back.paras.last, ParaStyle.body);
      expect(_only(back).cells, 2);
    });
  });

  group('textFromHtml', () {
    test('Chrome: a web page table with thead / tbody', () {
      const html =
          '<html><body><!--StartFragment--><p style="color: rgb(32, 33, 36);">Prices:</p>'
          '<table class="wikitable" style="border-collapse: collapse; color: rgb(32, 33, 36);">'
          '<thead><tr><th style="background-color: rgb(234, 236, 240); padding: 0.2em;">Fruit'
          '</th><th style="background-color: rgb(234, 236, 240);">Price</th></tr></thead>\n'
          '<tbody><tr><td style="padding: 0.2em;">Apple</td><td><b>1.20</b></td></tr>\n'
          '<tr><td>Pear<br>(ripe)</td><td><span style="color: rgb(200, 0, 0);">0.90</span></td>'
          '</tr></tbody></table><p>Fresh daily.</p><!--EndFragment--></body></html>';
      final d = textFromHtml(html, _box)!;
      expect(d.text, 'Prices:\nFruit\nPrice\nApple\n1.20\nPear (ripe)\n0.90\nFresh daily.');
      final t = _only(d);
      expect(t.line, 1);
      expect(t.columns, 2);
      expect(t.spec.header, isTrue);
      expect(t.spec.widths, [0.5, 0.5]);
      // Header cells are bold by the table; cell shading is no highlight.
      expect(_styleOf(d, 'Fruit'), SpanStyle.plain);
      expect(_styleOf(d, '1.20'), const SpanStyle(bold: true));
      expect(_styleOf(d, '0.90'), const SpanStyle(color: 0xFFC80000));
    });

    test('Firefox: a partial table without tbody; th not on the first row', () {
      const html =
          '<html><body>\n<!--StartFragment--><table><tr><td>1</td><td>2</td><td>3</td></tr>'
          '<tr><th>Total</th><td colspan="2">6</td></tr><tr><td>x</td></tr>'
          '</table><!--EndFragment-->\n</body></html>';
      final d = textFromHtml(html, _box)!;
      expect(_cells(d), ['1', '2', '3', 'Total', '6', '', 'x', '', '']);
      expect(_only(d).spec.header, isFalse);
      expect(_styleOf(d, 'Total'), const SpanStyle(bold: true));
      expect(d.text.endsWith('\n'), isTrue); // A line after the table.
    });

    test('Word: MsoTableGrid, widths in pt, paragraphs and o:p in cells', () {
      const html =
          'Version:0.9\r\nStartHTML:0000000105\r\nEndHTML:0000003000\r\n'
          'StartFragment:0000000527\r\nEndFragment:0000002950\r\n'
          '<html xmlns:o="urn:schemas-microsoft-com:office:office" '
          'xmlns:w="urn:schemas-microsoft-com:office:word">'
          '<head><style><!-- p.MsoNormal {margin:0cm;} --></style></head>'
          '<body lang=EN-GB style=\'tab-interval:36.0pt\'><!--StartFragment-->'
          '<p class=MsoNormal>Team list<o:p></o:p></p>\r\n'
          '<table class=MsoTableGrid border=1 cellspacing=0 cellpadding=0 '
          'style=\'border-collapse:collapse;border:none;mso-border-alt:solid windowtext .5pt;'
          'mso-yfti-tbllook:1184;mso-padding-alt:0cm 5.4pt 0cm 5.4pt\'>\r\n'
          ' <tr style=\'mso-yfti-irow:0;mso-yfti-firstrow:yes\'>\r\n'
          '  <td width=104 valign=top style=\'width:77.9pt;border:solid windowtext 1.0pt;'
          'mso-border-alt:solid windowtext .5pt;padding:0cm 5.4pt 0cm 5.4pt\'>\r\n'
          '  <p class=MsoNormal style=\'margin-bottom:0cm;line-height:normal\'><b>Name<o:p>'
          '</o:p></b></p>\r\n  </td>\r\n'
          '  <td width=312 valign=top style=\'width:233.7pt;border:solid windowtext 1.0pt;'
          'border-left:none;padding:0cm 5.4pt 0cm 5.4pt\'>\r\n'
          '  <p class=MsoNormal style=\'margin-bottom:0cm;line-height:normal\'><b>Role<o:p>'
          '</o:p></b></p>\r\n  </td>\r\n </tr>\r\n'
          ' <tr style=\'mso-yfti-irow:1;mso-yfti-lastrow:yes\'>\r\n'
          '  <td width=104 valign=top style=\'width:77.9pt;border:solid windowtext 1.0pt;'
          'border-top:none;padding:0cm 5.4pt 0cm 5.4pt\'>\r\n'
          '  <p class=MsoNormal style=\'margin-bottom:0cm;line-height:normal\'>Ada<o:p></o:p>'
          '</p>\r\n  </td>\r\n'
          '  <td width=312 valign=top style=\'width:233.7pt;border-top:none;'
          'padding:0cm 5.4pt 0cm 5.4pt\'>\r\n'
          '  <p class=MsoNormal style=\'margin-bottom:0cm;line-height:normal\'><i>Lead</i>'
          '<o:p></o:p></p>\r\n'
          '  <p class=MsoNormal style=\'margin-bottom:0cm;line-height:normal\'>since 2020'
          '<o:p></o:p></p>\r\n  </td>\r\n </tr>\r\n'
          ' <![if !supportMisalignedColumns]>\r\n <tr height=0>\r\n'
          '  <td width=104 style=\'border:none\'></td>\r\n'
          '  <td width=312 style=\'border:none\'></td>\r\n </tr>\r\n <![endif]>\r\n'
          '</table>\r\n'
          '<p class=MsoNormal><o:p>&nbsp;</o:p></p>\r\n'
          '<p class=MsoNormal>After<o:p></o:p></p>\r\n'
          '<!--EndFragment--></body></html>';
      final d = textFromHtml(html, _box)!;
      expect(d.text, 'Team list\nName\nRole\nAda\nLead since 2020\n \nAfter');
      final t = _only(d);
      expect(t.rows, 2); // (Not Word's row for misaligned columns.)
      expect(t.spec.header, isFalse);
      expect(t.spec.widths[0], closeTo(0.25, 0.001));
      expect(_styleOf(d, 'Name'), const SpanStyle(bold: true));
      expect(_styleOf(d, 'Lead'), const SpanStyle(italic: true));
      expect(_styleOf(d, 'since'), SpanStyle.plain);
    });

    test('LibreOffice Writer: <col> widths, <p> in cells, an empty cell', () {
      const html =
          '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">\n<html><head>'
          '<meta http-equiv="content-type" content="text/html; charset=utf-8"/>'
          '<title></title><style type="text/css">p { margin-bottom: 0.25cm }</style></head>'
          '<body lang="en-GB" dir="ltr"><p style="margin-bottom: 0cm">Plan</p>\n'
          '<table width="642" cellpadding="7" cellspacing="0">\n'
          '\t<col width="128"/>\n\t<col width="256"/>\n\t<col width="214"/>\n'
          '\t<tr valign="top">\n'
          '\t\t<td width="128" style="border: 1px solid #000000; padding: 0.18cm">'
          '<p><font color="#c9211e">Mon</font></p></td>\n'
          '\t\t<td width="256" style="border: 1px solid #000000; padding: 0.18cm">'
          '<p><u>Gym</u></p></td>\n'
          '\t\t<td width="214" style="border: 1px solid #000000; padding: 0.18cm">'
          '<p><br/></p></td>\n\t</tr>\n'
          '\t<tr valign="top">\n'
          '\t\t<td style="border: 1px solid #000000"><p>Tue</p></td>\n'
          '\t\t<td style="border: 1px solid #000000"><ul><li><p>Swim</p></li>'
          '<li><p>Run</p></li></ul></td>\n'
          '\t\t<td style="border: 1px solid #000000"><p><s>Rest</s></p></td>\n'
          '\t</tr>\n</table>\n<p style="margin-bottom: 0cm">Done</p></body></html>';
      final d = textFromHtml(html, _box)!;
      expect(d.text, 'Plan\nMon\nGym\n\nTue\nSwim Run\nRest\nDone');
      final t = _only(d);
      expect(t.columns, 3);
      expect(t.spec.widths[0], closeTo(128 / 598, 0.001));
      expect(t.spec.widths[1], closeTo(256 / 598, 0.001));
      expect(_styleOf(d, 'Mon'), const SpanStyle(color: 0xFFC9211E));
      expect(_styleOf(d, 'Gym'), const SpanStyle(underline: true));
      expect(_styleOf(d, 'Rest'), const SpanStyle(strike: true));
      expect(d.paras.first, ParaStyle.body);
    });

    test('Google Docs: colgroup widths, <p dir="ltr"> and spans in cells', () {
      const html =
          '<meta charset="utf-8"><b style="font-weight:normal;" id="docs-internal-guid-1a2b">'
          '<p dir="ltr" style="line-height:1.38;margin-top:0pt;margin-bottom:0pt;">'
          '<span style="font-size:11pt;font-family:Arial,sans-serif;color:#000000;'
          'font-weight:400;">Above</span></p>'
          '<div dir="ltr" style="margin-left:0pt;" align="left">'
          '<table style="border:none;border-collapse:collapse;"><colgroup>'
          '<col width="100" /><col width="300" /></colgroup><tbody>'
          '<tr style="height:0pt"><td style="border-left:solid #000000 1pt;'
          'vertical-align:top;padding:5pt 5pt 5pt 5pt;overflow:hidden;overflow-wrap:break-word;">'
          '<p dir="ltr" style="line-height:1.2;margin-top:0pt;margin-bottom:0pt;">'
          '<span style="font-size:11pt;font-family:Arial,sans-serif;color:#000000;'
          'font-weight:700;">Key</span></p></td>'
          '<td style="border-left:solid #000000 1pt;vertical-align:top;padding:5pt;">'
          '<p dir="ltr" style="line-height:1.2;margin-top:0pt;margin-bottom:0pt;">'
          '<span style="font-size:11pt;font-family:Arial,sans-serif;color:#1155cc;'
          'font-weight:400;text-decoration:underline;">Value</span></p></td></tr>'
          '<tr style="height:0pt"><td style="vertical-align:top;padding:5pt;">'
          '<p dir="ltr" style="line-height:1.2;margin-top:0pt;margin-bottom:0pt;">'
          '<span style="font-size:11pt;font-family:Arial,sans-serif;color:#000000;'
          'font-weight:400;font-style:italic;">k2</span></p></td>'
          '<td style="vertical-align:top;padding:5pt;"><br></td></tr>'
          '</tbody></table></div><br /><p dir="ltr" style="line-height:1.38;margin-top:0pt;'
          'margin-bottom:0pt;"><span style="font-size:11pt;font-family:Arial,sans-serif;'
          'color:#000000;font-weight:400;">Below</span></p></b><br class="Apple-interchange-newline">';
      final d = textFromHtml(html, _box)!;
      expect(d.text, 'Above\nKey\nValue\nk2\n\n\nBelow');
      final t = _only(d);
      expect(t.spec.widths, [0.25, 0.75]);
      expect(_styleOf(d, 'Key'), const SpanStyle(bold: true));
      expect(_styleOf(d, 'Value'), const SpanStyle(color: 0xFF1155CC, underline: true));
      expect(_styleOf(d, 'k2'), const SpanStyle(italic: true));
    });

    test('nested tables flatten into their cell; captions are skipped', () {
      const html =
          '<table><caption>Title</caption><tr><td>outer</td><td>'
          '<table><tr><td>in1</td><td>in2</td></tr><tr><td>in3</td></tr></table></td></tr>'
          '<tr><td>last</td><td>row</td></tr></table>';
      final d = textFromHtml(html, _box)!;
      expect(_cells(d), ['outer', 'in1 in2 in3', 'last', 'row']);
    });

    test('at most 12 columns; extra cells dropped', () {
      final row = [for (var i = 0; i < 14; i++) '<td>c$i</td>'].join();
      final d = textFromHtml('<p>a</p><table><tr>$row</tr></table><p>b</p>', _box)!;
      expect(_only(d).columns, TableSpec.maxColumns);
      expect(_cells(d).last, 'c11');
      expect(d.text, endsWith('c11\nb'));
    });

    test('two tables in a row stay apart', () {
      const html = '<table><tr><td>a</td></tr></table><table><tr><td>b</td></tr></table>';
      final d = textFromHtml(html, _box)!;
      final tables = TextTables.of(d.paras);
      expect(tables.length, 2);
      expect(d.text, 'a\n\nb\n');
    });
  });

  group('textFromRtf', () {
    test('Word: a 2 × 2 table with formatting, header row, text around it', () {
      const rtf =
          r'{\rtf1\adeflang1025\ansi\ansicpg1252\uc1\adeff31507\deff0'
          r'{\fonttbl{\f0\fbidi \froman\fcharset0\fprq2 Times New Roman;}'
          r'{\f31506\fbidi \froman\fcharset0\fprq2 Calibri;}}'
          r'{\colortbl;\red0\green0\blue0;\red255\green0\blue0;}'
          r'{\*\generator Microsoft Word 16.0;}'
          '\n'
          r'\pard\plain \ltrpar\ql \li0\ri0\sa160\sl259\slmult1\widctlpar\wrapdefault\itap0 '
          r'\fs22 {\insrsid1 Before the table}{\par }'
          '\n'
          r'\trowd \irow0\irowband0\ltrrow\ts11\trgaph108\trleft-108\trhdr\trbrdrt\brdrs\brdrw10 '
          r'\trftsWidth1\trautofit1\trpaddl108\trpaddr108\tblind0\tblindtype3 '
          r'\clvertalt\clbrdrt\brdrs\brdrw10 \cltxlrtb\clftsWidth3\clwWidth3005\clshdrawnil '
          r'\cellx2897\clvertalt\clbrdrt\brdrs\brdrw10 \cltxlrtb\clftsWidth3\clwWidth6011 '
          r'\cellx8908\pard\plain \ltrpar\ql \li0\ri0\widctlpar\intbl\wrapdefault\aspalpha\aspnum\faauto\adjustright\rin0\lin0\yts11 \fs22 '
          r'{\b\insrsid1 Name}{\insrsid1 \cell }{\b\insrsid1 Role\cell }'
          r'\pard\plain \ltrpar\ql \li0\ri0\sa160\sl259\slmult1\widctlpar\intbl\wrapdefault '
          r'\fs22 {\insrsid1 \trowd \irow0\irowband0\ltrrow\ts11\trgaph108\trleft-108\trhdr'
          r'\clvertalt\cltxlrtb\clftsWidth3\clwWidth3005 \cellx2897\clvertalt\cltxlrtb'
          r'\clftsWidth3\clwWidth6011 \cellx8908\row }'
          '\n'
          r'\trowd \irow1\irowband1\lastrow \ltrrow\ts11\trgaph108\trleft-108 '
          r'\clvertalt\cltxlrtb\clftsWidth3\clwWidth3005 \cellx2897\clvertalt\cltxlrtb'
          r'\clftsWidth3\clwWidth6011 \cellx8908\pard\plain \ltrpar\ql \li0\ri0\widctlpar'
          r'\intbl\wrapdefault\yts11 \fs22 {\cf2\insrsid1 Ada}{\insrsid1 \cell }'
          r'{\i\insrsid1 Lead}{\insrsid1 \par }{\insrsid1 since 2020\cell }'
          r'\pard\plain \ltrpar\ql \li0\ri0\widctlpar\intbl\wrapdefault \fs22 {\insrsid1 '
          r'\trowd \irow1\irowband1\lastrow \ltrrow\trgaph108\trleft-108 \cellx2897\cellx8908'
          r'\row }'
          '\n'
          r'\pard\plain \ltrpar\ql \li0\ri0\sa160\sl259\slmult1\widctlpar\wrapdefault\itap0 '
          r'\fs22 {\insrsid1 After}{\par }}';
      final d = textFromRtf(rtf, _box)!;
      expect(d.text, 'Before the table\nName\nRole\nAda\nLead since 2020\nAfter');
      final t = _only(d);
      expect(t.line, 1);
      expect(t.columns, 2);
      expect(t.spec.header, isTrue);
      expect(t.spec.widths[0], closeTo(3005 / 9016, 0.001));
      expect(_styleOf(d, 'Name'), const SpanStyle(bold: true));
      expect(_styleOf(d, 'Ada'), const SpanStyle(color: 0xFFFF0000));
      expect(_styleOf(d, 'Lead'), const SpanStyle(italic: true));
    });

    test('LibreOffice: a 3 × 3 table, a short row, a table ending the text', () {
      const rtf =
          r'{\rtf1\ansi\deff3\adeflang1025'
          '\n'
          r'{\fonttbl{\f0\froman\fprq2\fcharset0 Times New Roman;}'
          r'{\f3\fswiss\fprq2\fcharset0 Liberation Sans;}}'
          r'{\colortbl;\red0\green0\blue0;\red0\green0\blue255;}'
          r'{\stylesheet{\s0\snext0 Default Paragraph Style;}{\s20\snext20 Table Contents;}}'
          r'{\*\generator LibreOffice/7.6.4.1$Linux_X86_64 LibreOffice_project/1}'
          '\n'
          r'\pgndec\pard\plain \s0\rtlch\af3\afs24 \ltrch\hich\af3\loch\f3\fs24 '
          r'{\rtlch \ltrch\loch Intro}\par '
          r'\trowd\trql\trleft0\ltrrow\trpaddft3\trpaddt0\trpaddfl3\trpaddl55\trpaddfb3'
          r'\trpaddb55\trpaddfr3\trpaddr55\clbrdrt\brdrs\brdrw10\brdrcf1\cellx3213'
          r'\clbrdrt\brdrs\brdrw10\brdrcf1\cellx6426\clbrdrt\brdrs\brdrw10\brdrcf1\cellx9638'
          r'\pgndec\pard\plain \s20\intbl\rtlch\af3 \ltrch\loch\f3\fs24 '
          r'{\rtlch \ltrch\loch\b A1}\cell\pard\plain \s20\intbl\ltrch\loch\f3 '
          r'{\rtlch \ltrch\loch\cf2 A2}\cell\pard\plain \s20\intbl\ltrch\loch\f3 '
          r'{\rtlch \ltrch\loch A3}\cell\row\pard'
          r'\trowd\trql\trleft0\ltrrow\cellx3213\cellx6426\cellx9638'
          r'\pgndec\pard\plain \s20\intbl\ltrch\loch\f3 {\rtlch \ltrch\loch\ul B1}\cell'
          r'\pard\plain \s20\intbl\ltrch\loch\f3 \cell'
          r'\pard\plain \s20\intbl\ltrch\loch\f3 {\rtlch \ltrch\loch B3}\cell\row\pard'
          r'\trowd\trql\trleft0\ltrrow\cellx3213\cellx6426'
          r'\pgndec\pard\plain \s20\intbl\ltrch\loch\f3 {\rtlch \ltrch\loch\strike C1}\cell'
          r'\pard\plain \s20\intbl\ltrch\loch\f3 {\rtlch \ltrch\loch C2}\cell\row\pard}';
      final d = textFromRtf(rtf, _box)!;
      expect(d.text, 'Intro\nA1\nA2\nA3\nB1\n\nB3\nC1\nC2\n\n');
      final t = _only(d);
      expect(t.columns, 3);
      expect(t.spec.header, isFalse);
      expect(t.spec.widths[0], closeTo(3213 / 9638, 0.001));
      expect(_styleOf(d, 'A1'), const SpanStyle(bold: true));
      expect(_styleOf(d, 'A2'), const SpanStyle(color: 0xFF0000FF));
      expect(_styleOf(d, 'B1'), const SpanStyle(underline: true));
      expect(_styleOf(d, 'C1'), const SpanStyle(strike: true));
      expect(d.paras.last, ParaStyle.body);
    });

    test('Word nested tables flatten into the outer cell', () {
      const rtf =
          r'{\rtf1\ansi\deff0{\fonttbl{\f0 Calibri;}}'
          r'\trowd\cellx3000\cellx6000\pard\intbl\itap1 outer\cell '
          r'\pard\intbl\itap2 in1\nestcell in2\nestcell '
          r'{\*\nesttableprops\trowd\cellx1000\cellx2000\nestrow}{\nonesttables\par }'
          r'\pard\intbl\itap1 tail\cell '
          r'\pard\intbl\itap1 {\trowd\cellx3000\cellx6000\row}'
          r'\pard\itap0 After\par}';
      final d = textFromRtf(rtf, _box)!;
      expect(_cells(d), ['outer', 'in1 in2 tail']);
      expect(d.text, endsWith('\nAfter'));
    });
  });
}
