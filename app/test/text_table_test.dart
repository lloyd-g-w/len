import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/rich_text_buffer.dart';
import 'package:len/domain/text/table_edits.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/domain/text/text_record.dart';

/// A box: "Intro", a 2 × 2 table (a b / c d), "End".
TextData sample({bool header = false}) {
  final spec = TableSpec(const [0.25, 0.75], header: header);
  return TextData.rich(
    text: 'Intro\na\nb\nc\nd\nEnd',
    spans: const [StyledRange(6, 7, SpanStyle(bold: true))],
    paras: [
      ParaStyle.body,
      ParaStyle(cell: TableCell(spec, first: true)),
      ParaStyle(cell: TableCell(spec)),
      ParaStyle(cell: TableCell(spec)),
      ParaStyle(cell: TableCell(spec)),
      ParaStyle.body,
    ],
  );
}

List<String> cellTexts(RichTextBuffer b, TextTable t) => [
  for (var l = t.line; l < t.end; l++) b.lineAt(l).text,
];

void main() {
  group('TableSpec', () {
    test('widths are shares summing to 1, none narrower than the minimum', () {
      final s = TableSpec(const [1, 3]);
      expect(s.widths, [0.25, 0.75]);
      final thin = TableSpec(const [0, 100, 100]);
      expect(thin.widths.first, greaterThan(0.03));
      expect(thin.widths.fold(0.0, (a, b) => a + b), closeTo(1, 1e-9));
      expect(TableSpec.even(3).widths, [0.3333, 0.3333, 0.3334]);
    });
  });

  group('stored form', () {
    test('round trip: the spec on the first cell, the others marked', () {
      final data = sample(header: true);
      final json = data.toJson();
      expect(json['paras'], [
        {},
        {
          'tb': {
            'c': 2,
            'w': [0.25, 0.75],
            'h': true,
          },
        },
        {'tc': true},
        {'tc': true},
        {'tc': true},
        {},
      ]);
      expect(TextData.fromJson(json), data);
      expect(TextRecord.parse(json), data);
      final tables = TextTables.of(TextRecord.parse(json).paras);
      expect(tables, [
        TextTable(1, 4, TableSpec(const [0.25, 0.75], header: true)),
      ]);
      // Header cells are marked (derived): the first row only.
      final paras = TextData.fromJson(json).paras;
      expect([for (final p in paras) p.cell?.header], [null, true, true, false, false, null]);
    });

    test('old data reads unchanged; an old reader sees cells as paragraphs', () {
      final plain = TextData.rich(
        text: 'a\nb',
        paras: const [ParaStyle(heading: 1), ParaStyle.body],
      );
      expect(TextRecord.parse(plain.toJson()), plain);
      // What a client without tables keeps of the cells: body lines.
      final json = sample().toJson();
      expect(json['text'], 'Intro\na\nb\nc\nd\nEnd');
    });

    test('strict parsing rejects malformed tables', () {
      Map<String, Object?> withParas(List<Object?> paras, [String text = 'a\nb']) => {
        ...TextData(text: text).toJson(),
        'paras': paras,
      };
      void bad(List<Object?> paras, [String text = 'a\nb']) => expect(
        () => TextRecord.parse(withParas(paras, text)),
        throwsFormatException,
        reason: '$paras',
      );
      final tb = {
        'c': 2,
        'w': [0.5, 0.5],
        'h': false,
      };
      expect(
        TextRecord.parse(
          withParas([
            {'tb': tb},
            {'tc': true},
          ]),
        ).paras.first.isCell,
        isTrue,
      );
      bad([
        {},
        {'tc': true},
      ]); // A cell without a table.
      bad([
        {'tb': tb},
        {},
      ]); // Half a row.
      bad([
        {
          'tb': {...tb, 'c': 3},
        },
        {'tc': true},
      ]);
      bad([
        {
          'tb': {...tb, 'h': 1},
        },
        {'tc': true},
      ]);
      bad([
        {
          'tb': {
            ...tb,
            'w': [0.5, -1],
          },
        },
        {'tc': true},
      ]);
      bad([
        {'tb': tb, 'h': 1},
        {'tc': true},
      ]);
      bad([
        {'tb': tb},
        {'tc': 1},
      ]);
      // Continuing a table from the page before: only the first line.
      expect(
        TextRecord.parse(
          withParas([
            {
              'tb': {...tb, 'k': true},
            },
            {'tc': true},
          ]),
        ).paras.first.cell!.spec.continued,
        isTrue,
      );
      bad([
        {},
        {
          'tb': {...tb, 'k': true},
        },
        {'tc': true},
      ], 'x\na\nb');
    });
  });

  group('plain text', () {
    test('rows as tab-separated lines', () {
      final d = sample();
      expect(TextTables.plainText(d.text, d.paras), 'Intro\na\tb\nc\td\nEnd');
      final end = TextData.rich(
        text: 'a\nb',
        paras: [
          ParaStyle(cell: TableCell(TableSpec.even(2), first: true)),
          ParaStyle(cell: TableCell(TableSpec.even(2))),
        ],
      );
      expect(TextTables.plainText(end.text, end.paras), 'a\tb');
    });
  });

  group('TableEdits', () {
    test('insert a table in an empty box: cells, then a line', () {
      final b = RichTextBuffer(const TextData());
      final t = b.insertTable(0, 2, 3);
      expect(t, TextTable(0, 6, TableSpec.even(3)));
      expect(b.lineCount, 7);
      expect(b.para(6), ParaStyle.body);
      expect(b.para(0).cell!.first, isTrue);
      expect(b.para(1).cell!.first, isFalse);
    });

    test('insert splits a line, goes above or below it', () {
      final b = RichTextBuffer(const TextData(text: 'Hello'));
      b.insertTable(2, 1, 2);
      expect(b.text, 'He\n\n\nllo');
      final above = RichTextBuffer(const TextData(text: 'Hello'))..insertTable(0, 1, 1);
      expect(above.text, '\nHello');
      expect(above.para(0).isCell, isTrue);
      final below = RichTextBuffer(const TextData(text: 'Hello'))..insertTable(5, 1, 1);
      expect(below.text, 'Hello\n\n');
      expect([for (final p in below.paras) p.isCell], [false, true, false]);
    });

    test('rows and columns', () {
      final b = RichTextBuffer(sample(header: true));
      var t = b.tables.single;
      t = b.insertRow(t, 1);
      expect(cellTexts(b, t), ['a', 'b', '', '', 'c', 'd']);
      t = b.insertColumn(t, 1);
      expect(cellTexts(b, t), ['a', '', 'b', '', '', '', 'c', '', 'd']);
      expect(t.spec.widths.fold(0.0, (a, b) => a + b), closeTo(1, 1e-3));
      expect(t.spec.widths[1], closeTo(1 / 3, 1e-3));
      t = b.removeColumn(t, 0)!;
      expect(cellTexts(b, t), ['', 'b', '', '', '', 'd']);
      t = b.removeRow(t, 0)!;
      expect(cellTexts(b, t), ['', '', '', 'd']);
      // The header row is the first row, whatever was removed.
      expect(
        [for (var l = t.line; l < t.end; l++) b.para(l).cell!.header],
        [true, true, false, false],
      );
      expect(b.para(t.line).cell!.first, isTrue);
      expect(b.text, 'Intro\n\n\n\nd\nEnd');
      b.removeTable(t);
      expect(b.text, 'Intro\nEnd');
      expect(b.tables, isEmpty);
    });

    test('removing the last row or column removes the table', () {
      final b = RichTextBuffer(const TextData())..insertTable(0, 1, 2);
      expect(b.removeRow(b.tables.single, 0), isNull);
      expect(b.tables, isEmpty);
      final c = RichTextBuffer(const TextData())..insertTable(0, 2, 1);
      expect(c.removeColumn(c.tables.single, 0), isNull);
      expect(c.text, '');
    });

    test('cells take text without breaks; formatting kept', () {
      final b = RichTextBuffer(sample());
      b.setCell(2, 'x\ny', const [SpanStyle(italic: true), SpanStyle.plain, SpanStyle.plain]);
      expect(b.lineAt(2).text, 'x y');
      expect(b.charStyle(b.lineStart(2)).italic, isTrue);
      expect(b.para(2).isCell, isTrue);
    });

    test('header and widths', () {
      final b = RichTextBuffer(sample());
      final t = b.setSpec(b.tables.single, TableSpec(const [0.5, 0.5], header: true));
      expect(b.para(t.line).cell!.spec.header, isTrue);
      expect(b.para(t.line + 1).cell!.header, isTrue);
      expect(b.para(t.line + 2).cell!.header, isFalse);
    });

    test('repair: a short row filled, a line after a final table', () {
      final spec = TableSpec.even(2);
      final b = RichTextBuffer(
        TextData.rich(
          text: 'a\nb\nc',
          paras: [
            ParaStyle(cell: TableCell(spec, first: true)),
            ParaStyle(cell: TableCell(spec)),
            ParaStyle(cell: TableCell(spec)),
          ],
        ),
      );
      expect(b.repairTables(), isTrue);
      expect(b.text, 'a\nb\nc\n\n');
      expect(b.tables.single.cells, 4);
      expect(b.para(4), ParaStyle.body);
      expect(b.repairTables(), isFalse);
    });

    test('list and heading commands leave cells alone', () {
      final p = ParaStyle(cell: TableCell(TableSpec.even(1), first: true));
      expect(p.copyWith(heading: 1, list: ListKind.bullet), p);
    });
  });

  group('flow', () {
    test('a part beginning inside a table continues it, and joins back', () {
      final whole = sample(header: true);
      // Split before row 2 ("c").
      final at = whole.text.indexOf('c');
      final head = TextFlow.slice(whole, 0, at - 1);
      final rest = TextFlow.slice(
        whole,
        at,
        whole.text.length,
      ).withFlow(const TextFlow(from: 'head'));
      final first = rest.paras.first.cell!;
      expect(first.first, isTrue);
      expect(first.spec.continued, isTrue);
      expect(first.header, isFalse, reason: 'no header row on the next page');
      expect(TextRecord.parse(rest.toJson()), rest);
      expect(TextFlow.join([head, rest]), whole);
    });
  });
}
