import 'package:flutter_test/flutter_test.dart';
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
}
