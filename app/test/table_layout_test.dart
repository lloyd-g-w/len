import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/rich_text_buffer.dart';
import 'package:len/domain/text/table_edits.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/elements/text_flow_layout.dart';
import 'package:len/ink/elements/text_layout.dart';

import 'content_golden_test.dart' show loadFonts;

/// "Shopping" (heading), a 3 × 2 table with a header (Item / Price …), and
/// a closing line.
TextData shopping({ParagraphSpacing spacing = ParagraphSpacing.none}) {
  final b = RichTextBuffer(const TextData(text: 'Shopping\nTotal is fine'));
  final t = b.insertTable(9, 3, 2, header: true);
  final cells = ['Item', 'Price', 'Bread, a long loaf of sourdough', '3.20', 'Milk', '1.10'];
  for (var k = 0; k < cells.length; k++) {
    final text = cells[k];
    b.setCell(t.line + k, text, List.filled(text.length, const SpanStyle()));
  }
  b.updateParas(0, 0, (p) => p.copyWith(heading: 2));
  b.updateChars(
    b.lineStart(t.line + 4),
    b.lineStart(t.line + 4) + 4,
    (s) => s.copyWith(italic: true),
  );
  return b.toData(TextData(fontSize: 20, spacing: spacing));
}

const double width = 320;

class _Painted extends CustomPainter {
  _Painted(this.data);
  final TextData data;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = TextLayout.layout(data, width);
    layout.paint(canvas, Offset.zero);
    layout.dispose();
  }

  @override
  bool shouldRepaint(_Painted old) => false;
}

void main() {
  setUpAll(loadFonts);

  test('a row is one placeholder line standing for its cells', () {
    final data = shopping();
    final layout = TextLayout.layout(data, width);
    expect(layout.rows, hasLength(3));
    expect(layout.painter.computeLineMetrics(), hasLength(5));
    final offsets = layout.offsets;
    // Display: heading, three rows, last line.
    expect(offsets.display(data.text), 'Shopping\n\uFFFC\n\uFFFC\n\uFFFC\nTotal is fine');
    final bread = data.text.indexOf('Bread');
    expect(offsets.isInRow(bread), isTrue);
    expect(
      offsets.toModel(offsets.toDisplay(data.text.indexOf('Total'))),
      data.text.indexOf('Total'),
    );
    // The caret never rests by a row.
    final row = offsets.charAt(bread);
    expect(offsets.isHidden(row), isTrue);
    expect(offsets.isHidden(row + 1), isTrue);
    // The long cell wraps: its row is taller than the header's.
    final rows = layout.rows;
    expect(rows[1].rect.height, greaterThan(rows[0].rect.height * 1.5));
    expect(rows[0].rect.width, closeTo(width, 0.1));
    layout.dispose();
  });

  test('boxes and hit tests inside cells', () {
    final data = shopping();
    final layout = TextLayout.layout(data, width);
    final milk = data.text.indexOf('Milk');
    final boxes = layout.boxesOf(milk, milk + 4);
    expect(boxes, hasLength(1));
    final rows = layout.rows;
    final box = boxes.single.toRect();
    expect(rows[2].rect.contains(box.center), isTrue);
    expect(box.left, lessThan(width / 2));
    final hit = layout.cellAt(box.center + const Offset(8, 0));
    expect(hit!.line, 5);
    expect(hit.offset, inInclusiveRange(1, 3));
    final price = data.text.indexOf('1.10');
    expect(layout.boxesOf(price, price + 4).single.left, greaterThan(width / 2));
    // A range over the table and text takes both.
    expect(layout.boxesOf(0, data.text.length).length, greaterThan(6));
    layout.dispose();
  });

  test('paragraph spacing goes below the table, not between its rows', () {
    final plain = TextLayout.layout(shopping(), width);
    final spaced = TextLayout.layout(shopping(spacing: ParagraphSpacing.large), width);
    final a = plain.rows, b = spaced.rows;
    expect(b[1].rect.top - b[0].rect.top, closeTo(a[1].rect.top - a[0].rect.top, 0.5));
    // Heading → table and table → last line: 20 each.
    expect(spaced.height - plain.height, closeTo(40, 1));
    plain.dispose();
    spaced.dispose();
  });

  test('right-to-left boxes put the first column on the right', () {
    final b = RichTextBuffer(const TextData(text: 'שלום'));
    final t = b.insertTable(4, 1, 2);
    b.setCell(t.line, 'א', const [SpanStyle()]);
    final data = b.toData(const TextData());
    final layout = TextLayout.layout(data, width);
    final box = layout.boxesOf(data.text.indexOf('א'), data.text.indexOf('א') + 1).single;
    expect(box.left, greaterThan(width / 2));
    layout.dispose();
  });

  test('auto-width boxes give tables a width per column', () {
    final data = shopping();
    final w = TextLayout.naturalWidth(data.copyWith(autoWidth: true));
    expect(
      w,
      greaterThanOrEqualTo(
        TableLayout.naturalWidth(
          data,
          data.paras.isEmpty ? throw '' : TextTables.of(data.paras).single,
        ),
      ),
    );
  });

  test('a table splits between rows across pages', () {
    final data = shopping();
    final layout = TextLayout.layout(data, width);
    final rows = layout.rows;
    // Room for the heading, the header row and half the next.
    final room = rows[1].rect.top + rows[1].rect.height / 2;
    final parts = TextFlowLayout.split(layout, (_) => room);
    expect(parts.length, greaterThan(1));
    final second = parts[1].dataOf(data, from: 'a');
    expect(second.text.startsWith('Bread'), isTrue);
    final cell = second.paras.first.cell!;
    expect(cell.first && cell.spec.continued, isTrue);
    expect(
      TextFlow.join([
        for (final (k, p) in parts.indexed) p.dataOf(data, from: k == 0 ? null : 'a'),
      ]),
      data,
    );
    layout.dispose();
  });

  testWidgets('a table painted (golden)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final data = shopping();
    final height = TextLayout.heightOf(data, width);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Align(
              alignment: Alignment.topLeft,
              child: CustomPaint(size: Size(width, height), painter: _Painted(data)),
            ),
          ),
        ),
      ),
    );
    await expectLater(find.byType(ColoredBox), matchesGoldenFile('goldens/table_layout.png'));
  });
}
