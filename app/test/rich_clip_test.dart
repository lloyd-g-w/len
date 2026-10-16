import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/html_writer.dart';
import 'package:len/domain/text/rich_text_buffer.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/tools/text/rich_text_controller.dart';

import 'rich_text_test.dart' show select, type;

/// Text copied in a box and pasted back in Len (its own clipboard format).
void main() {
  const highlight = 0xFFFFE066;

  test('a paste of Len\'s own copy keeps its characters as copied', () {
    // "AB": only "B" highlighted. Copy "A", paste after "B".
    final c = RichTextController(
      TextData.rich(
        text: 'AA BB',
        spans: const [StyledRange(3, 5, SpanStyle(highlight: highlight))],
      ),
    );
    select(c, 0, 2);
    c.copyNow();
    select(c, 5, 5);
    type(c, 'AA');
    final chars = c.data.charStyles();
    expect(c.data.text, 'AA BBAA');
    expect(chars[5], SpanStyle.plain);
    expect(chars[6], SpanStyle.plain);
  });

  test('typing what was last copied is typing, not a paste', () {
    final c = RichTextController(TextData.rich(text: 'ab'));
    select(c, 0, 1);
    c.toggleBold();
    c.copyNow();
    select(c, 2, 2);
    type(c, 'a');
    expect(c.data.charStyles()[2].bold, isFalse);
    // A copied line break: Enter after a heading is still body text.
    final h = RichTextController(
      TextData.rich(
        text: 'Title\nitem',
        paras: const [
          ParaStyle(heading: 1),
          ParaStyle(list: ListKind.bullet),
        ],
      ),
    );
    select(h, 5, 6);
    h.copyNow();
    select(h, 10, 10);
    type(h, '\n');
    expect(h.data.paras.last.list, ListKind.bullet);
    expect(h.data.paras.last.heading, 0);
    // A copied space doesn't stop "- " from starting a list.
    final s = RichTextController(TextData.rich(text: 'x y\n'));
    select(s, 1, 2);
    s.copyNow();
    select(s, 4, 4);
    type(s, '-');
    type(s, ' ');
    expect(s.data.paras.last.list, ListKind.bullet);
  });

  test('a copy that ends at the start of a line leaves that line\'s style behind', () {
    final b = RichTextBuffer(
      TextData.rich(
        text: 'Title\nitem',
        paras: const [
          ParaStyle(heading: 1),
          ParaStyle(list: ListKind.bullet),
        ],
      ),
    );
    final slice = b.slice(0, 6, const TextData());
    expect(slice.text, 'Title\n');
    expect(slice.paras.last, ParaStyle.body);
    expect(htmlFromText(slice), isNot(contains('<li>')));
    // Pasted into the middle of a line, the rest of that line keeps its
    // own style.
    final into = RichTextBuffer(
      TextData.rich(
        text: 'xy',
        paras: const [ParaStyle(list: ListKind.number)],
      ),
    )..insertRich(1, 1, b.slice(0, 6, const TextData()), SpanStyle.plain);
    expect(into.text, 'xTitle\ny');
    expect(into.para(1).list, ListKind.number);
  });
}
