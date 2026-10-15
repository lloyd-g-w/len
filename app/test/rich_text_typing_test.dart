import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/tools/text/rich_text_controller.dart';

import 'rich_text_test.dart' show type;

/// Types [text] one character at a time.
void typeEach(RichTextController c, String text) {
  for (final ch in text.split('')) {
    type(c, ch);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('lists by typing', () {
    test('"- ", "1. " and "[] " at a line start start lists; undo gives them back', () {
      final c = RichTextController(const TextData());
      typeEach(c, '- milk');
      expect(c.data.text, 'milk');
      expect(c.data.paras.single.list, ListKind.bullet);
      typeEach(c, '\neggs'); // the list goes on
      expect(c.data.paras.map((p) => p.list), [ListKind.bullet, ListKind.bullet]);

      final n = RichTextController(const TextData());
      typeEach(n, '1. first');
      expect((n.data.text, n.data.paras.single.list), ('first', ListKind.number));

      final t = RichTextController(const TextData());
      typeEach(t, '[] call');
      expect((t.data.text, t.data.paras.single.list), ('call', ListKind.check));
      t.undo(); // the word
      t.undo(); // the list
      expect((t.data.text, t.data.paras.single.list), ('[] ', ListKind.none));
    });

    test('elsewhere the characters stay', () {
      final c = RichTextController(const TextData());
      typeEach(c, 'a - b 1. c');
      expect(c.data.text, 'a - b 1. c');
      expect(c.data.paras.single.list, ListKind.none);
      // On a list line "- " is text.
      final l = RichTextController(const TextData())..toggleList(ListKind.bullet);
      typeEach(l, '- x');
      expect((l.data.text, l.data.paras.single.list), ('- x', ListKind.bullet));
    });
  });
}
