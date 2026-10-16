import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/elements/text_flow_layout.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/ink/elements/text_layout_cache.dart';

/// Lines of body text, one paragraph each.
String lines(int n) => [for (var i = 0; i < n; i++) 'Line $i'].join('\n');

/// [whole] split as [TextFlowLayout] does, each part with its flow.
List<TextData> partsOf(TextData whole, double width, double room) {
  final layout = TextLayout.layout(whole, width);
  final parts = TextFlowLayout.split(layout, (_) => room);
  layout.dispose();
  return [for (final (k, p) in parts.indexed) p.dataOf(whole, from: k == 0 ? null : 'box$k')];
}

void main() {
  group('TextFlow codec', () {
    test('round trip, trailing zero counts dropped', () {
      const flow = TextFlow(from: 'a', joined: true, numbers: [3, 1], direction: TextDirection.rtl);
      expect(TextFlow.fromJson(flow.toJson()), flow);
      expect(
        TextFlow.fromJson({
          'from': 'a',
          'joined': false,
          'numbers': [2, 0, 0],
          'dir': 'ltr',
        })!.numbers,
        [2],
      );
      final data = TextData.rich(text: 'x').withFlow(flow);
      expect(TextData.fromJson(data.toJson()), data);
      expect(data.toJson()['flow'], {
        'from': 'a',
        'joined': true,
        'numbers': [3, 1],
        'dir': 'rtl',
      });
    });

    test('malformed flows are dropped (the box stands alone)', () {
      for (final bad in <Object?>[
        'a',
        <String, Object?>{'from': 'a', 'joined': true, 'dir': 'ltr'},
        {'from': 'a', 'joined': true, 'numbers': <int>[]},
        {'from': 'a', 'joined': true, 'numbers': <int>[], 'dir': 'up'},
        {'from': '', 'joined': true, 'numbers': <int>[]},
        {'from': 3, 'joined': true, 'numbers': <int>[]},
        {'from': 'a', 'joined': 'yes', 'numbers': <int>[]},
        {
          'from': 'a',
          'joined': true,
          'numbers': [-1],
        },
        {
          'from': 'a',
          'joined': true,
          'numbers': [1.5],
        },
        {
          'from': 'a',
          'joined': true,
          'numbers': [1, 1, 1, 1, 1, 1],
        },
      ]) {
        expect(TextFlow.fromJson(bad), isNull, reason: '$bad');
        expect(TextData.fromJson({'text': 'x', 'flow': bad}).flow, isNull);
      }
    });

    test('a box no longer continuing drops the stored flow', () {
      final stored = TextData.rich(text: 'x')
          .withFlow(const TextFlow(from: 'a'))
          .toJson({'other': 1});
      final json = TextData.rich(text: 'y').toJson(stored);
      expect(json.containsKey('flow'), isFalse);
      expect(json['other'], 1);
    });
  });

  group('slice and join', () {
    final whole = TextData.rich(
      text: 'Title\none two three\nfour',
      spans: [
        const StyledRange(2, 5, SpanStyle(bold: true)),
        const StyledRange(6, 9, SpanStyle(bold: true)),
      ],
      paras: [
        const ParaStyle(heading: 1),
        const ParaStyle(list: ListKind.bullet),
        ParaStyle.body,
      ],
      fontSize: 20,
    );

    test('a paragraph split inside joins back without a break', () {
      final a = TextFlow.slice(whole, 0, 10);
      final b = TextFlow.slice(
        whole,
        10,
        whole.text.length,
      ).withFlow(const TextFlow(from: 'a', joined: true));
      expect(a.text, 'Title\none ');
      expect(a.spans, [
        const StyledRange(2, 5, SpanStyle(bold: true)),
        const StyledRange(6, 9, SpanStyle(bold: true)),
      ]);
      expect(b.text, 'two three\nfour');
      expect(b.paras.first.list, ListKind.bullet);
      expect(TextFlow.join([a, b]), whole);
    });

    test('a split between paragraphs drops the break, and join puts it back', () {
      final a = TextFlow.slice(whole, 0, 5);
      final b = TextFlow.slice(whole, 6, whole.text.length).withFlow(const TextFlow(from: 'a'));
      expect(b.paras.first.list, ListKind.bullet);
      expect(b.spans, [const StyledRange(0, 3, SpanStyle(bold: true))]);
      expect(TextFlow.join([a, b]), whole);
    });
  });

  group('continued lists', () {
    test('numbers run on; a continued item shows no marker but keeps its indent', () {
      final paras = [
        const ParaStyle(list: ListKind.number),
        const ParaStyle(list: ListKind.number),
        const ParaStyle(list: ListKind.number, indent: 1),
        const ParaStyle(list: ListKind.number),
      ];
      expect(TextFlow.numbersAfter(paras.sublist(0, 2)), [2]);
      expect(TextFlow.numbersAfter(paras.sublist(0, 3)), [2, 1]);
      expect(TextFlow.numbersAfter([ParaStyle.body]), isEmpty);

      final data = TextData.rich(
        text: 'rest of two\nthree',
        paras: [
          const ParaStyle(list: ListKind.number),
          const ParaStyle(list: ListKind.number),
        ],
      ).withFlow(const TextFlow(from: 'a', joined: true, numbers: [1]));
      final markers = TextLayout.markersOf(data);
      expect([for (final m in markers) m.label], ['2.', '3.']);
      expect(markers.first.continued, isTrue);
      final layout = TextLayout.layout(data, 400);
      expect(layout.markers.map((m) => m.label), ['3.']);
      expect(layout.markerBoxes, hasLength(1));
      // The first line starts where the item's text does.
      final first = layout.painter.getOffsetForCaret(
        TextPosition(offset: layout.offsets.toDisplay(0)),
        Rect.zero,
      );
      expect(first.dx, closeTo(markers.first.size.width, 0.5));
      layout.dispose();
    });
  });

  group('split', () {
    test('everything fitting stays one part', () {
      final whole = TextData.rich(text: lines(3));
      final layout = TextLayout.layout(whole, 300);
      final parts = TextFlowLayout.split(layout, (_) => 1000);
      expect(parts, hasLength(1));
      expect(parts.single.height, layout.height);
      layout.dispose();
    });

    test('paragraphs split at line boundaries, each part as tall as its room allows', () {
      final whole = TextData.rich(text: lines(20));
      final line = TextLayout.heightOf(TextData.rich(text: 'x'), 300);
      final parts = partsOf(whole, 300, line * 6.5);
      expect(parts.map((p) => p.lineCount), [6, 6, 6, 2]);
      expect(parts[1].flow!.joined, isFalse);
      expect(TextFlow.join(parts), whole);
    });

    test('a long paragraph splits mid-paragraph and joins back', () {
      final whole = TextData.rich(text: List.filled(80, 'word').join(' '));
      final line = TextLayout.heightOf(TextData.rich(text: 'x'), 200);
      final parts = partsOf(whole, 200, line * 3.2);
      expect(parts.length, greaterThan(2));
      for (final p in parts.skip(1)) {
        expect(p.flow!.joined, isTrue);
        expect(TextLayout.heightOf(p, 200), lessThanOrEqualTo(line * 3.2));
      }
      expect(TextFlow.join(parts), whole);
    });

    test('a wrapped list item continues with a hanging indent and running numbers', () {
      final items = [for (var i = 0; i < 6; i++) 'item $i ${List.filled(12, 'abc').join(' ')}'];
      final whole = TextData.rich(
        text: items.join('\n'),
        paras: [for (final _ in items) const ParaStyle(list: ListKind.number)],
      );
      final full = TextLayout.layout(whole, 240);
      final line = full.painter.computeLineMetrics().first.height;
      full.dispose();
      final parts = partsOf(whole, 240, line * 5);
      expect(parts.length, greaterThan(2));
      expect(TextFlow.join(parts), whole);
      // Each part, laid out alone, is as tall as its lines in the whole.
      final layout = TextLayout.layout(whole, 240);
      final split = TextFlowLayout.split(layout, (_) => line * 5);
      for (final (k, p) in parts.indexed) {
        expect(TextLayout.heightOf(p, 240), closeTo(split[k].height, 0.01));
        final markers = TextLayout.markersOf(p);
        final numbered = [
          for (final m in markers)
            if (!m.continued) m.number,
        ];
        // Numbers count on from the parts before.
        final before = TextFlow.join(parts.sublist(0, k + 1)).lineCount - p.lineCount;
        if (numbered.isNotEmpty) {
          final firstShown = markers.firstWhere((m) => !m.continued);
          expect(firstShown.number, before + firstShown.line + 1);
        }
      }
      layout.dispose();
    });

    test('at least one line per part, however little room', () {
      final whole = TextData.rich(text: lines(3), fontSize: 40);
      final parts = partsOf(whole, 300, 1);
      expect(parts.map((p) => p.text), ['Line 0', 'Line 1', 'Line 2']);
    });
  });

  test('the layout cache lays out once per text and width', () {
    final cache = TextLayoutCache();
    final data = TextData.rich(text: 'hello');
    final a = cache.of(data, 100);
    expect(identical(cache.of(TextData.rich(text: 'hello'), 100), a), isTrue);
    expect(identical(cache.of(data, 120), a), isFalse);
    expect(cache.naturalWidth(data), TextLayout.naturalWidth(data));
    cache.dispose();
  });
}
