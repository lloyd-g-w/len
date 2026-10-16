import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/html_text.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/clipboard/clipboard_mirror.dart';
import 'package:len/ink/elements/text_edit_session.dart';
import 'package:len/ink/elements/text_flow_chains.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/ink/images/element_images.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/selection_controller.dart';

import 'data_test.dart' show FakeClock;
import 'text_flow_session_test.dart' show FakePages;

/// [n] Hebrew lines.
String hebrew(int n) => [for (var i = 0; i < n; i++) 'שורה $i'].join('\n');

/// One right-to-left paragraph whose words after the first are Latin, so a
/// part of it may begin with a left-to-right word.
final String mixedParagraph = 'שלום ${List.filled(160, 'word').join(' ')}';

/// The left edge of each line of [layout].
List<double> lefts(TextBoxLayout layout) => [
  for (final l in layout.painter.computeLineMetrics()) l.left,
];

void main() {
  group('split', () {
    test('a right-to-left paragraph split mid-way keeps its direction and lines', () {
      final whole = TextData.rich(
        text: mixedParagraph,
        paras: const [ParaStyle(list: ListKind.bullet)],
        fontSize: 18,
      );
      const width = 300.0;
      final layout = TextLayout.layout(whole, width);
      addTearDown(layout.dispose);
      expect(layout.plan.base, TextDirection.rtl);
      final parts = TextFlowLayout.split(layout, (_) => 200);
      expect(parts.length, greaterThan(1));
      final next = parts[1].dataOf(whole, from: 'head');
      // On its own the part would read left to right ("word word …").
      expect(next.text, startsWith('word'));
      expect(next.flow!.joined, isTrue);
      expect(next.flow!.direction, TextDirection.rtl);
      expect(TextData.fromJson(next.toJson()).directions, [TextDirection.rtl]);

      final first = parts[0].dataOf(whole);
      final a = TextLayout.layout(first, width), b = TextLayout.layout(next, width);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      expect(b.plan.base, TextDirection.rtl);
      // The continued item shows no bullet but keeps its indent, on the right.
      expect(b.markers, isEmpty);
      // Each part lays out its lines where the whole text has them.
      final all = lefts(layout);
      final n = lefts(a).length;
      for (final (i, x) in lefts(a).indexed) {
        expect(x, closeTo(all[i], 0.01), reason: 'line $i');
      }
      for (final (i, x) in lefts(b).indexed) {
        expect(x, closeTo(all[n + i], 0.01), reason: 'line ${n + i}');
      }
    });

    test('a numbered right-to-left list runs on, its labels on the right', () {
      final whole = TextData.rich(
        text: hebrew(12),
        paras: [for (var i = 0; i < 12; i++) const ParaStyle(list: ListKind.number)],
      );
      final layout = TextLayout.layout(whole, 300);
      addTearDown(layout.dispose);
      final parts = TextFlowLayout.split(layout, (_) => 150);
      expect(parts.length, greaterThan(1));
      final next = parts[1].dataOf(whole, from: 'head');
      final before = parts[0].dataOf(whole).lineCount;
      expect(next.flow!.joined, isFalse);
      expect(next.flow!.numbers, [before]);
      final b = TextLayout.layout(next, 300);
      addTearDown(b.dispose);
      final m = b.markers.first;
      expect((m.number, m.direction), (before + 1, TextDirection.rtl));
      // The label sits on the text side (left) of the right-hand column.
      final column = m.column(b.markerBoxes.first);
      expect(column.right, closeTo(300, 1));
      final label = TextBoxLayout.numberPainter(m, m.label);
      addTearDown(label.dispose);
      expect(TextBoxLayout.numberOrigin(m, label, column).dx, lessThan(column.center.dx));
    });
  });

  group('the editing field', () {
    test('page breaks in right-to-left and mixed paragraphs: rooms the caret skips', () {
      for (final whole in [
        TextData.rich(text: mixedParagraph),
        TextData.rich(text: 'English first\n$mixedParagraph'),
      ]) {
        final layout = TextLayout.layout(whole, 300);
        final parts = TextFlowLayout.split(layout, (_) => 120);
        layout.dispose();
        final at = parts[1].start;
        expect(parts[1].joined, isTrue);
        final plan = TextPlan.of(whole, 300, breaks: [(at: at, gap: 90, soft: true)]);
        final o = plan.offsets;
        final room = o.roomOf(at)!;
        expect(plan.wraps, contains(at));
        expect(o.display(whole.text).substring(room, room + 2), '\uFFFC\n');
        expect(o.isPageBreak(room), isTrue);
        expect(o.isHidden(room), isTrue);
        expect(o.isHidden(room + 1), isTrue);
        // The part's start shows after the room; the end of the part before
        // is a place for the caret too.
        expect(o.toDisplay(at), greaterThan(room + 1));
        expect(o.isHidden(o.toDisplay(at)), isFalse);
        expect(o.toModel(o.toDisplay(at)), at);
        // Out of the room: up goes to the page before, down to the next.
        expect(o.toModel(o.allowedNear(room + 1, o.display(whole.text).length, step: -1)), at);
        expect(o.allowedNear(room, 1 << 20, step: 1), o.toDisplay(at));
      }
    });

    test('a page break before a right-to-left list item keeps the caret after its marker', () {
      final whole = TextData.rich(
        text: hebrew(4),
        paras: [for (var i = 0; i < 4; i++) const ParaStyle(list: ListKind.number)],
      );
      final at = whole.text.indexOf('\n') + 1;
      final plan = TextPlan.of(whole, 300, breaks: [(at: at, gap: 50, soft: false)]);
      final o = plan.offsets;
      final room = o.roomOf(at)!;
      // Room, its line break, then the marker: the caret rests after it.
      expect(o.isHidden(room), isTrue);
      expect(o.isHidden(room + 1), isTrue);
      expect(o.isHidden(room + 2), isTrue);
      expect(o.isMarker(room + 2), isTrue);
      expect(o.toDisplay(at), room + 3);
      expect(o.isHidden(room + 3), isFalse);
    });
  });

  group('chains', () {
    late AppDatabase db;
    late FakeClock clock;
    late ElementRepository elements;
    late FakePages pages;
    late TextFlowChains chains;
    late TextEditSession session;

    setUp(() {
      db = AppDatabase.inMemory();
      clock = FakeClock();
      elements = ElementRepository(db, deviceId: 'dev', clock: clock);
      final strokes = StrokeRepository(db, deviceId: 'dev', clock: clock);
      pages = FakePages(elements, strokes, ['p0', 'p1', 'p2']);
      chains = TextFlowChains(pages, clock: clock);
      session = TextEditSession(model: pages.modelOf('p0'), clock: clock)..flows = chains;
    });

    tearDown(() {
      session.dispose();
      pages.models.dispose();
      db.close();
    });

    void typeBox(TextData data) {
      session.create(const Offset(40, 600), style: const TextData(), width: 300);
      session.setData(data);
      session.end();
    }

    test('a right-to-left box flows; its continuation reads right to left', () {
      typeBox(TextData.rich(text: mixedParagraph));
      final head = elements.allOn('p0').single;
      final next = elements.allOn('p1').single;
      final flow = TextChains.flowOf(next)!;
      expect((flow.from, flow.joined, flow.direction), (head.id, true, TextDirection.rtl));
      expect(next.rect.left, head.rect.left);
      expect(
        TextFlowChains.wholeOf(head, chains.continuationsOf('p0', head.id)).text,
        mixedParagraph,
      );
      // Opened again, the field shows a soft page break.
      session.edit(head);
      final breaks = session.breaksFor(session.data);
      expect(breaks.first.soft, isTrue);
      expect(breaks.first.at, TextData.fromJson(head.data).text.length);
      session.end();
    });

    test('lasso copy of a chain writes the whole text as HTML', () async {
      String? sent, sentHtml;
      final mirror = ClipboardMirror(
        images: ElementImages(read: (_) async => null, fetch: (_) async => false),
        write: ({png, text, html}) async {
          await png;
          sent = text;
          sentHtml = html;
          return true;
        },
      );
      final selection = SelectionController(
        model: pages.modelOf('p0'),
        clipboard: InkClipboard(mirror: mirror.copy),
        clock: clock,
      )..flows = chains;
      addTearDown(selection.dispose);
      final whole = TextData.rich(
        text: '${hebrew(14)}\nEnglish end',
        paras: [
          const ParaStyle(heading: 1),
          for (var i = 1; i < 15; i++) const ParaStyle(list: ListKind.bullet),
        ],
      );
      typeBox(whole);
      expect(elements.allOn('p1'), isNotEmpty);
      selection
        ..select(const [], [pages.modelOf('p0').elementById(elements.allOn('p0').single.id)!])
        ..copy();
      expect(await mirror.written, isTrue);
      final html = sentHtml;
      expect(sent, whole.text);
      expect(html, contains('<h1 dir="rtl">שורה 0</h1>'));
      expect(html, contains('<li dir="rtl">שורה 13</li>'));
      expect(html, contains('<li>English end</li>'));
      // What other apps get reads back as the whole text, styles and all.
      final read = textFromHtml(html!, const TextData())!;
      expect(read.text, whole.text);
      expect(read.paras, whole.paras);
    });
  });
}

/// Reads a stored box's flow.
abstract final class TextChains {
  static TextFlow? flowOf(SurfaceElement e) => TextFlowChains.flowOf(e);
}
