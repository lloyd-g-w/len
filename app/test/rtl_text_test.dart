import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/tools/text/rich_text_controller.dart';
import 'package:len/ink/elements/text_layout.dart';

import 'rich_text_test.dart' show backspace, type;

/// A Hebrew note: a heading, a paragraph that wraps, a bulleted item that
/// wraps, a numbered item.
final TextData hebrew = TextData.rich(
  text:
      'רשימת קניות\n'
      'צריך לקנות חלב טרי ולחם מהמאפייה בדרך הביתה\n'
      'ביצים, גבינה לבנה ועגבניות מהשוק הקטן\n'
      'להתקשר לסבתא',
  paras: const [
    ParaStyle(heading: 2),
    ParaStyle.body,
    ParaStyle(list: ListKind.bullet),
    ParaStyle(list: ListKind.number),
  ],
  fontSize: 20,
);

/// English, then Hebrew and Arabic paragraphs (one a wrapping list item),
/// then English again.
final TextData mixed = TextData.rich(
  text:
      'Meeting notes\n'
      'שלום לכולם, הפגישה תתחיל בשעה 10 בבוקר\n'
      'مرحبا بالجميع في الاجتماع الأسبوعي للفريق\n'
      'Back to English (with עברית inside)',
  paras: const [
    ParaStyle.body,
    ParaStyle(list: ListKind.bullet),
    ParaStyle.body,
    ParaStyle.body,
  ],
  fontSize: 20,
);

const double width = 260;

/// Model offsets of the lines of [data] (start, end without the break).
List<(int, int)> paragraphs(TextData data) {
  final out = <(int, int)>[];
  var start = 0;
  while (true) {
    final nl = data.text.indexOf('\n', start);
    out.add((start, nl < 0 ? data.text.length : nl));
    if (nl < 0) return out;
    start = nl + 1;
  }
}

/// The laid-out boxes of [start, end) grouped by line, each line's left
/// and right extent (spaces left out).
List<({int line, double left, double right})> lines(TextBoxLayout l, int start, int end) {
  final metrics = l.painter.computeLineMetrics();
  int lineAt(double y) {
    var top = 0.0;
    for (final m in metrics) {
      if (y < top + m.height) return m.lineNumber;
      top += m.height;
    }
    return metrics.length - 1;
  }

  final byLine = <int, ({int line, double left, double right})>{};
  for (var i = start; i < end; i++) {
    if (l.data.text[i] == ' ') continue;
    for (final b in l.boxesOf(i, i + 1)) {
      final key = lineAt((b.top + b.bottom) / 2);
      final was = byLine[key];
      byLine[key] = (
        line: key,
        left: math.min(was?.left ?? b.left, b.left),
        right: math.max(was?.right ?? b.right, b.right),
      );
    }
  }
  return byLine.values.toList()..sort((a, b) => a.line.compareTo(b.line));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('right-to-left layout', () {
    test('a Hebrew box runs right to left: lines, markers and indents on the right', () {
      final l = TextLayout.layout(hebrew, width);
      expect(l.plan.base, TextDirection.rtl);
      expect(l.painter.textDirection, TextDirection.rtl);
      final paras = paragraphs(hebrew);
      // Start-aligned: every line ends at the right edge.
      for (final (s, e) in [paras[0], paras[1]]) {
        final ls = lines(l, s, e);
        for (final line in ls) {
          expect(line.right, closeTo(width, 0.5));
        }
      }
      expect(lines(l, paras[1].$1, paras[1].$2), hasLength(greaterThan(1)));
      // The markers sit on the right, the item's lines hang left of them.
      final boxes = l.markerBoxes;
      expect(boxes, hasLength(2));
      for (var k = 0; k < 2; k++) {
        final marker = l.markers[k];
        expect(marker.direction, TextDirection.rtl);
        expect(boxes[k].right, closeTo(width, 0.5));
        final (s, e) = paras[marker.line];
        final item = lines(l, s, e);
        for (final line in item) {
          expect(line.right, closeTo(width - marker.size.width, 0.5));
        }
      }
      expect(lines(l, paras[2].$1, paras[2].$2), hasLength(greaterThan(1)));
      // Bullets draw at the column's outer side, numbers read ".1".
      final bullet = l.markers.first;
      final disc = bullet.shapes(boxes.first).single.rect.center.dx;
      expect(disc, greaterThan(boxes.first.center.dx));
      final label = TextBoxLayout.numberPainter(l.markers.last, '1.');
      final origin = TextBoxLayout.numberOrigin(
        l.markers.last,
        label,
        l.markers.last.column(boxes.last),
      );
      expect(origin.dx, lessThan(boxes.last.center.dx));
      label.dispose();
      l.dispose();
    });

    test('end alignment puts Hebrew lines on the left, centre in the middle', () {
      for (final (align, edge) in [(TextAlignment.end, 0.0), (TextAlignment.center, null)]) {
        final data = hebrew.copyWith(align: align);
        final l = TextLayout.layout(data, width);
        final (s, e) = paragraphs(data)[1];
        for (final line in lines(l, s, e)) {
          if (edge != null) {
            expect(line.left, closeTo(edge, 0.5));
          } else {
            expect((line.left + line.right) / 2, closeTo(width / 2, 0.5));
          }
        }
        l.dispose();
      }
    });

    test('each paragraph runs and aligns in its own direction', () {
      for (final align in TextAlignment.values) {
        final data = mixed.copyWith(align: align);
        final l = TextLayout.layout(data, width);
        expect(l.plan.base, TextDirection.ltr);
        expect(l.plan.directions, [
          TextDirection.ltr,
          TextDirection.rtl,
          TextDirection.rtl,
          TextDirection.ltr,
        ]);
        final paras = paragraphs(data);
        for (var p = 0; p < paras.length; p++) {
          final rtl = l.plan.directions[p] == TextDirection.rtl;
          final marker = l.markers.where((m) => m.line == p).firstOrNull;
          final indent = marker?.size.width ?? 0;
          final ls = lines(l, paras[p].$1, paras[p].$2);
          if (p == 1 || p == 2) expect(ls, hasLength(greaterThan(1)), reason: 'para $p wraps');
          for (final line in ls) {
            final reason = '$align, paragraph $p';
            switch ((align, rtl)) {
              case (TextAlignment.start, true) || (TextAlignment.end, false):
                expect(line.right, closeTo(width - (rtl ? indent : 0), 0.6), reason: reason);
              case (TextAlignment.start, false) || (TextAlignment.end, true):
                expect(line.left, closeTo(rtl ? 0 : indent, 0.6), reason: reason);
              case (TextAlignment.center, _):
                final mid = (line.left + line.right + (rtl ? indent : -indent)) / 2;
                expect(mid, closeTo(width / 2, 1), reason: reason);
            }
            expect(line.left, greaterThanOrEqualTo(-0.01));
            expect(line.right, lessThanOrEqualTo(width + 0.01));
          }
        }
        // The Hebrew item's bullet is on the right of its text.
        final box = l.markerBoxes.single;
        final (s, e) = paras[1];
        expect(box.left, greaterThanOrEqualTo(lines(l, s, e).first.right - 0.5));
        // The Hebrew words read right to left: the first one is rightmost.
        final first = l.boxesOf(s, s + 4).first, second = l.boxesOf(s + 5, s + 10).first;
        expect(first.left, greaterThan(second.right));
        // No line runs over: one laid-out line per planned line.
        for (final p in [1, 2]) {
          final (s, e) = paras[p];
          final planned = 1 + l.wraps.where((w) => w > s && w < e).length;
          expect(lines(l, s, e), hasLength(planned), reason: '$align, paragraph $p');
        }
        l.dispose();
      }
    });

    test('auto-width boxes are as wide as their longest line in either direction', () {
      final data = mixed.copyWith(autoWidth: true);
      final w = TextLayout.naturalWidth(data);
      final l = TextLayout.layout(data, w);
      expect(l.wraps, isEmpty);
      expect(l.painter.computeLineMetrics(), hasLength(4));
      final (s, e) = paragraphs(data)[2];
      // Start-aligned Arabic: on the right edge of the box.
      expect(lines(l, s, e).single.right, closeTo(w, 0.5));
      l.dispose();
    });

    test('Arabic is shaped by the bundled font (joined, narrower than its letters)', () {
      const word = 'مرحبا';
      final joined = TextLayout.naturalWidth(TextData(text: word));
      final apart = TextLayout.naturalWidth(TextData(text: word.split('').join(' ')));
      final spaces = TextLayout.naturalWidth(const TextData(text: '    '));
      expect(joined, lessThan(apart - spaces));
      expect(joined, greaterThan(TextLayout.minWidth));
    });
  });

  group('editing right-to-left text', () {
    RichTextController controller(TextData data) => RichTextController(data)..wrapWidth = width;

    test('the field lays out the text exactly as the box', () {
      for (final data in [hebrew, mixed, mixed.copyWith(align: TextAlignment.center)]) {
        final c = controller(data);
        final l = TextLayout.layout(data, width);
        expect(c.text, l.offsets.display(data.text));
        expect(c.plan.inserts, l.plan.inserts);
        expect(c.plan.base, l.plan.base);
        l.dispose();
      }
    });

    test('typing into a paragraph of the other direction keeps the text whole', () {
      final c = controller(mixed);
      final (_, end) = paragraphs(mixed)[2];
      c.selection = TextSelection.collapsed(offset: c.plan.offsets.toDisplay(end));
      type(c, ' اليوم');
      expect(c.data.text, contains('للفريق اليوم\n'));
      expect(c.modelSelection, TextRange.collapsed(end + 6));
      final l = TextLayout.layout(c.data, width);
      expect(c.text, l.offsets.display(c.data.text));
      l.dispose();
      // Enter there starts a right-to-left paragraph.
      type(c, '\n');
      expect(c.caretDirection, TextDirection.rtl);
      type(c, 'abc');
      expect(c.caretDirection, TextDirection.ltr);
    });

    test('the caret never rests among isolates and padding', () {
      final c = controller(mixed.copyWith(align: TextAlignment.center));
      final offsets = c.plan.offsets;
      for (var d = 0; d <= c.text.length; d++) {
        c.selection = TextSelection.collapsed(offset: d);
        final at = c.selection.baseOffset;
        expect(offsets.isHidden(at), isFalse, reason: 'at $d');
        expect(at, inInclusiveRange(0, c.text.length));
      }
      // Arrowing through the whole text visits every model offset.
      final seen = <int>{};
      c.selection = const TextSelection.collapsed(offset: 0);
      for (var k = 0; k < c.text.length * 2 && c.selection.baseOffset < c.text.length; k++) {
        seen.add(c.modelSelection.start);
        c.selection = TextSelection.collapsed(offset: c.selection.baseOffset + 1);
      }
      seen.add(c.modelSelection.start);
      expect(seen, {for (var i = 0; i <= mixed.text.length; i++) i});
    });

    test('a jump into the inserts before a line lands on that line (a click, Home, End)', () {
      final c = controller(mixed);
      final (start, _) = paragraphs(mixed)[1];
      final caret = c.plan.offsets.toDisplay(start);
      // Every hidden spot in front of the Hebrew line (padding, isolate,
      // marker) takes the caret to its start, not to the line above.
      for (var d = caret - 1; c.plan.offsets.isHidden(d); d--) {
        c.selection = const TextSelection.collapsed(offset: 0);
        c.selection = TextSelection.collapsed(offset: d);
        expect(c.modelSelection, TextRange.collapsed(start), reason: 'at $d');
      }
      // Home on the line's start keeps it there.
      c.selection = TextSelection.collapsed(offset: caret);
      c.selection = TextSelection.collapsed(offset: c.plan.offsets.charAt(start) - 3);
      expect(c.modelSelection, TextRange.collapsed(start));
      // End of the Arabic line: after its closing isolate, still its end.
      final (_, end) = paragraphs(mixed)[2];
      c.selection = const TextSelection.collapsed(offset: 0);
      c.selection = TextSelection.collapsed(offset: c.plan.offsets.toDisplay(end) + 1);
      expect(c.modelSelection, TextRange.collapsed(end));
    });

    test('backspace at the start of a paragraph of the other direction joins it', () {
      final c = controller(mixed);
      final (start, _) = paragraphs(mixed)[2];
      c.selection = TextSelection.collapsed(offset: c.plan.offsets.toDisplay(start));
      backspace(c);
      expect(c.data.text, mixed.text.replaceRange(start - 1, start, ''));
      expect(c.modelSelection, TextRange.collapsed(start - 1));
      // At a wrapped line's start it deletes the space before the wrap.
      final c2 = controller(mixed);
      final wrap = c2.plan.wraps.firstWhere((w) => w > start);
      c2.selection = TextSelection.collapsed(offset: c2.plan.offsets.toDisplay(wrap));
      backspace(c2);
      expect(c2.data.text, mixed.text.replaceRange(wrap - 1, wrap, ''));
    });

    test('the alignment and caret direction follow the caret paragraph', () {
      final c = controller(mixed);
      c.selection = TextSelection.collapsed(offset: c.plan.offsets.toDisplay(2));
      expect(c.caretDirection, TextDirection.ltr);
      final (start, _) = paragraphs(mixed)[1];
      c.selection = TextSelection.collapsed(offset: c.plan.offsets.toDisplay(start + 2));
      expect(c.caretDirection, TextDirection.rtl);
      expect(c.extentDirection, TextDirection.rtl);
    });
  });
}
