import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/tools/text/rich_text_controller.dart';
import 'package:len/ink/elements/text_layout.dart';

import 'rich_text_test.dart' show backspace, type;

/// Long bulleted (also nested), numbered and checklist items that wrap in
/// a box [wrappedListWidth] wide.
final TextData wrappedList = TextData.rich(
  text:
      'Lists\n'
      'A bullet item long enough to wrap onto more lines\n'
      'A nested bullet that also wraps over lines\n'
      'First numbered step that wraps here\n'
      'Second step\n'
      'A checklist item which wraps as well',
  paras: const [
    ParaStyle(heading: 2),
    ParaStyle(list: ListKind.bullet),
    ParaStyle(list: ListKind.bullet, indent: 1),
    ParaStyle(list: ListKind.number),
    ParaStyle(list: ListKind.number),
    ParaStyle(list: ListKind.check, checked: true),
  ],
  fontSize: 20,
);

const double wrappedListWidth = 260;

/// Left edge of the laid-out character at model offset [m].
double leftOf(TextBoxLayout layout, int m) {
  return layout.boxesOf(m, m + 1).first.left;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MarkerOffsets with wraps', () {
    test('a wrap inserts a break and a gap; its offset maps to the next line', () {
      final d = TextData.rich(
        text: 'ab cd',
        paras: const [ParaStyle(list: ListKind.bullet)],
      );
      final marker = TextLayout.markersOf(d).single;
      final m = MarkerOffsets([
        TextInsert(0, [InsertPiece.marker(marker)], caret: 1, allowed: {1}),
        TextInsert(
          3,
          [InsertPiece.lineBreak, InsertPiece.space(marker.size)],
          caret: 2,
          allowed: {0, 2},
        ),
      ]);
      expect(m.display(d.text), '\uFFFCab \n\uFFFCcd');
      expect(m.toDisplay(0), 1);
      expect(m.toDisplay(3), 6);
      expect(m.toModel(4), 3); // before the break: the end of the first line
      expect(m.toModel(5), 3);
      expect(m.toModel(6), 3);
      expect(m.toModel(7), 4);
      expect(m.isHidden(5), isTrue);
      expect(m.isHidden(4), isFalse);
      expect(
        [for (var i = 0; i < 8; i++) m.isInserted(i)],
        [
          true, false, false, false, true, true, false, false, //
        ],
      );
      expect(m.isMarker(0), isTrue);
      expect(m.isMarker(5), isFalse);
    });
  });

  group('hanging indents', () {
    test('continuation lines of list items start under the item text, at every level', () {
      final layout = TextLayout.layout(wrappedList, wrappedListWidth);
      final text = wrappedList.text;
      expect(layout.wraps, isNotEmpty);
      var start = 0;
      var wrappedItems = 0;
      for (var line = 0; line < wrappedList.paras.length; line++) {
        final end = text.indexOf('\n', start) < 0 ? text.length : text.indexOf('\n', start);
        final wraps = layout.wraps.where((w) => w > start && w < end).toList();
        if (wrappedList.paras[line].isList) {
          final textStart = leftOf(layout, start);
          final marker = layout.markers.firstWhere((m) => m.line == line);
          expect(textStart, closeTo(marker.size.width, 0.5), reason: 'line $line');
          for (final w in wraps) {
            expect(leftOf(layout, w), closeTo(textStart, 0.01), reason: 'wrap at $w');
          }
          if (wraps.isNotEmpty) wrappedItems++;
        } else {
          expect(wraps, isEmpty);
        }
        start = end + 1;
      }
      expect(wrappedItems, 4);
      // Breaks only where the items wrap: one line per paragraph and wrap.
      expect(
        layout.painter.computeLineMetrics(),
        hasLength(wrappedList.paras.length + layout.wraps.length),
      );
      // Marker boxes are only the markers, not the gaps.
      expect(layout.markerBoxes, hasLength(layout.markers.length));
      layout.dispose();
    });

    test('a wrapped line fits the width it had on its own', () {
      for (final width in [120.0, 180.0, 260.0, 400.0]) {
        final layout = TextLayout.layout(wrappedList, width);
        for (final l in layout.painter.computeLineMetrics()) {
          expect(l.left + l.width, lessThanOrEqualTo(width + 0.01));
        }
        layout.dispose();
      }
    });

    test('unbounded (auto-width) boxes do not wrap', () {
      expect(TextWraps.of(wrappedList, double.infinity), isEmpty);
      expect(TextLayout.naturalWidth(wrappedList), greaterThan(wrappedListWidth));
    });
  });

  group('editing wrapped items', () {
    RichTextController controller() =>
        RichTextController(wrappedList)..wrapWidth = wrappedListWidth;

    test('the field shows the same breaks and gaps as the box', () {
      final c = controller();
      final layout = TextLayout.layout(wrappedList, wrappedListWidth);
      expect(c.text, layout.offsets.display(wrappedList.text));
      expect(c.text, contains(MarkerOffsets.wrapText));
      expect(c.data.text, wrappedList.text);
      layout.dispose();
    });

    test('backspace at a continuation line deletes the character before the wrap', () {
      final c = controller();
      final w = TextWraps.of(wrappedList, wrappedListWidth).first;
      final offsets = MarkerOffsets.of(wrappedList, wrappedListWidth);
      c.selection = TextSelection.collapsed(offset: offsets.toDisplay(w));
      backspace(c);
      expect(c.data.text, wrappedList.text.replaceRange(w - 1, w, ''));
      expect(c.modelSelection, TextRange.collapsed(w - 1));
    });

    test('the caret steps over the gap of a wrap', () {
      final c = controller();
      final w = TextWraps.of(wrappedList, wrappedListWidth).first;
      final d = MarkerOffsets.of(wrappedList, wrappedListWidth).toDisplay(w);
      c.selection = TextSelection.collapsed(offset: d);
      c.selection = TextSelection.collapsed(offset: d - 1); // left arrow
      expect(c.selection.baseOffset, d - 2); // the end of the line above
      c.selection = TextSelection.collapsed(offset: d - 1); // right arrow
      expect(c.selection.baseOffset, d);
    });

    test('typing rewraps and keeps the caret in the text', () {
      final c = controller();
      final end = wrappedList.text.indexOf('\n', 6);
      c.selection = TextSelection.collapsed(
        offset: MarkerOffsets.of(c.data, wrappedListWidth).toDisplay(end),
      );
      type(c, ' and even more words');
      expect(c.data.text, contains('lines and even more words\n'));
      expect(c.modelSelection, TextRange.collapsed(end + 20));
      final layout = TextLayout.layout(c.data, wrappedListWidth);
      expect(c.text, layout.offsets.display(c.data.text));
      layout.dispose();
    });

    test('auto-width boxes edit without wraps', () {
      final c = RichTextController(wrappedList.copyWith(autoWidth: true))..wrapWidth = 100;
      expect(c.text, MarkerOffsets.of(c.data).display(c.data.text));
    });
  });
}
