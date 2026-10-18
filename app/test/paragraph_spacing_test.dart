import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/html_text.dart';
import 'package:len/domain/text/html_writer.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/domain/text/text_record.dart';
import 'package:len/features/search/editor/text_match_rects.dart';
import 'package:len/ink/elements/text_flow_layout.dart';
import 'package:len/ink/elements/text_layout.dart';

/// [text] in a 300-wide box at 20 units with [spacing].
TextData box(
  String text, {
  ParagraphSpacing spacing = ParagraphSpacing.medium,
  List<ParaStyle> paras = const [],
  List<StyledRange> spans = const [],
}) => TextData.rich(text: text, fontSize: 20, spacing: spacing, paras: paras, spans: spans);

/// The tops of [data]'s lines laid out [width] wide.
List<double> lineTops(TextData data, {double width = 300}) {
  final layout = TextLayout.layout(data, width);
  final tops = <double>[];
  var top = 0.0;
  for (final l in layout.painter.computeLineMetrics()) {
    tops.add(top);
    top += l.height;
  }
  layout.dispose();
  return tops;
}

/// The tight glyph boxes of the model text [start, end).
List<Rect> glyphs(TextData data, int start, int end) {
  final layout = TextLayout.layout(data, 300);
  final boxes = [for (final b in layout.boxesOf(start, end)) b.toRect()];
  layout.dispose();
  return boxes;
}

void main() {
  group('data', () {
    test('spacing is stored by name, left out for none; old data reads as none', () {
      final spaced = box('a\nb', spacing: ParagraphSpacing.large);
      expect(spaced.toJson()['spacing'], 'large');
      expect(TextData.fromJson(spaced.toJson()), spaced);
      expect(TextRecord.parse(spaced.toJson()), spaced);
      final plain = box('a\nb', spacing: ParagraphSpacing.none).toJson();
      expect(plain.containsKey('spacing'), isFalse);
      expect(TextRecord.parse(plain).spacing, ParagraphSpacing.none);
      // Turned off again, a stored value is dropped (not kept as unknown).
      expect(
        box('a', spacing: ParagraphSpacing.none).toJson(spaced.toJson()).containsKey('spacing'),
        isFalse,
      );
    });

    test('a malformed spacing makes the record malformed', () {
      final json = box('a\nb').toJson()..['spacing'] = 'huge';
      expect(() => TextRecord.parse(json), throwsFormatException);
      json['spacing'] = 2;
      expect(() => TextRecord.parse(json), throwsFormatException);
    });

    test('the gap follows the box size (lasso scaling scales it)', () {
      final data = box('a\nb');
      expect(data.paragraphGap, 10);
      expect(data.scaled(2).paragraphGap, 20);
      expect(data.copyWith(text: 'x').spacing, ParagraphSpacing.medium);
    });
  });

  test('sync carries the spacing; a box without it arrives as none', () {
    final a = AppServices.create(AppDatabase.inMemory());
    addTearDown(a.dispose);
    final nb = a.notebooks.create(
      title: 'Spacing',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final page = a.pages.pagesOf(nb.id).single.id;
    SurfaceElement element(String id, TextData data) => SurfaceElement(
      id: id,
      surfaceId: page,
      type: ElementType.text.name,
      rect: const Rect.fromLTWH(40, 60, 300, 90),
      z: 1,
      createdAt: 1,
      data: data.toJson(),
    );
    a.elements.save([
      element('spaced', box('a\nb', spacing: ParagraphSpacing.small)),
      element('plain', box('a\nb', spacing: ParagraphSpacing.none)),
    ]);
    final b = AppServices.create(AppDatabase.inMemory());
    addTearDown(b.dispose);
    final repo = ElementRepository(b.database, deviceId: 'b');
    for (final r in a.elements.dirtyRecords(10)) {
      final wire = jsonDecode(jsonEncode(r.data)) as Map<String, Object?>;
      if (r.id == 'plain') expect((wire['data']! as Map).containsKey('spacing'), isFalse);
      repo.writeRemote(
        SyncRecord(
          collection: 'elements',
          id: r.id,
          updatedAt: r.updatedAt,
          deviceId: 'a',
          deleted: false,
          data: wire,
        ),
      );
    }
    TextData of(String id) =>
        TextData.fromJson(repo.allOn(page).firstWhere((e) => e.id == id).data);
    expect(of('spaced').spacing, ParagraphSpacing.small);
    expect(of('spaced'), box('a\nb', spacing: ParagraphSpacing.small));
    expect(of('plain').spacing, ParagraphSpacing.none);
  });

  group('layout', () {
    test('each paragraph but the last gets the gap below; wrapped lines do not', () {
      const text = 'One\nTwo two two two two two two two two two two two two two two\nThree';
      final plain = lineTops(box(text, spacing: ParagraphSpacing.none));
      final spaced = lineTops(box(text));
      expect(spaced, hasLength(plain.length));
      expect(plain.length, greaterThan(3), reason: 'the second paragraph wraps');
      // Below the first paragraph, and below the second (not between its
      // wrapped lines).
      final shifts = [for (var i = 0; i < plain.length; i++) spaced[i] - plain[i]];
      expect(shifts[1], closeTo(10, 0.01));
      for (var i = 2; i < shifts.length - 1; i++) {
        expect(shifts[i], closeTo(10, 0.01), reason: 'wrapped line $i');
      }
      expect(shifts.last, closeTo(20, 0.01));
      // Nothing after the last paragraph.
      final h0 = TextLayout.heightOf(box(text, spacing: ParagraphSpacing.none), 300);
      expect(TextLayout.heightOf(box(text), 300), closeTo(h0 + 20, 0.01));
    });

    test('the text keeps its place on its line; glyph boxes and highlights stay tight', () {
      final hl = [StyledRange(0, 3, const SpanStyle(highlight: 0x80FFEB3B))];
      final plain = glyphs(box('One\nTwo', spacing: ParagraphSpacing.none, spans: hl), 0, 3);
      final spaced = glyphs(box('One\nTwo', spans: hl), 0, 3);
      expect(spaced.single.top, closeTo(plain.single.top, 0.01));
      expect(spaced.single.height, closeTo(plain.single.height, 0.01));
      final next = glyphs(box('One\nTwo'), 4, 7).single;
      final next0 = glyphs(box('One\nTwo', spacing: ParagraphSpacing.none), 4, 7).single;
      expect(next.top, closeTo(next0.top + 10, 0.01));
    });

    test('line-height boxes lose the spacing (PDF highlights)', () {
      final layout = TextLayout.layout(box('One\nTwo'), 300);
      final line = layout
          .boxesOf(0, 3, boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle)
          .single
          .toRect();
      final trimmed = layout.withoutSpacing(line);
      expect(line.height - trimmed.height, closeTo(10, 0.5));
      expect(layout.spacing.single.height, 10);
      layout.dispose();
    });

    test('larger text on the line: the gap is still the box\'s', () {
      final big = [StyledRange(0, 3, const SpanStyle(size: 40))];
      final plain = lineTops(box('One\nTwo', spacing: ParagraphSpacing.none, spans: big));
      final spaced = lineTops(box('One\nTwo', spans: big));
      expect(spaced[1], closeTo(plain[1] + 10, 0.01));
    });

    test('lists, empty paragraphs and paragraphs against the box\'s direction', () {
      const text = 'Item one\n\nשלום עולם\nEnd';
      final paras = [
        const ParaStyle(list: ListKind.bullet),
        const ParaStyle(list: ListKind.bullet),
        ParaStyle.body,
        ParaStyle.body,
      ];
      final plain = lineTops(box(text, spacing: ParagraphSpacing.none, paras: paras));
      final spaced = lineTops(box(text, paras: paras));
      expect(spaced, hasLength(plain.length));
      for (var i = 1; i < plain.length; i++) {
        expect(spaced[i], closeTo(plain[i] + 10 * i, 0.01), reason: 'line $i');
      }
      // The caret never rests after the spacing; the empty item's caret
      // is after its marker.
      final plan = TextPlan.of(box(text, paras: paras), 300);
      final spacing = [
        for (final i in plan.inserts)
          for (final (k, p) in i.pieces.indexed)
            if (p.kind == InsertKind.spacing) (i, k),
      ];
      expect(spacing, hasLength(3));
      for (final (insert, k) in spacing) {
        expect(insert.caret, lessThanOrEqualTo(k));
      }
      // The display text without inserts is the model text.
      expect(plan.offsets.toModel(plan.offsets.toDisplay(9)), 9);
    });
  });

  group('flow', () {
    test('a part may end in spacing past its room; the parts keep it between them', () {
      final data = box([for (var i = 0; i < 6; i++) 'Line $i'].join('\n'));
      final layout = TextLayout.layout(data, 300);
      final lines = layout.painter.computeLineMetrics();
      // Room for exactly three lines of text, not their spacing after.
      final room = lines[0].height * 3 - 10;
      final parts = TextFlowLayout.split(layout, (_) => room);
      layout.dispose();
      expect(parts.first.end, 'Line 0\nLine 1\nLine 2'.length);
      final first = parts.first.dataOf(data);
      expect(first.spacing, ParagraphSpacing.medium);
      final rest = parts[1].dataOf(data, from: 'a');
      expect(rest.spacing, ParagraphSpacing.medium);
      expect(TextFlow.join([first, rest]), data);
    });
  });

  group('search', () {
    test('a match after a spaced paragraph is highlighted where it is drawn', () {
      final data = box('Alpha\nBeta gamma');
      Rect match(TextData d) => textMatchRects(
        json: jsonEncode(d.toJson()),
        box: const Rect.fromLTWH(100, 50, 300, 200),
        rotation: 0,
        body: d.text,
        ranges: const [(start: 11, end: 16)],
      )!.single.single.rect;
      final plain = match(data.copyWith(spacing: ParagraphSpacing.none));
      final spaced = match(data);
      expect(spaced.top, closeTo(plain.top + 10, 0.01));
      expect(spaced.height, closeTo(plain.height, 0.01));
      final glyph = glyphs(data, 11, 16).single.shift(const Offset(100, 50));
      expect(spaced.top, closeTo(glyph.top, 0.01));
    });
  });

  group('html', () {
    test('copied as each block\'s bottom margin and read back', () {
      final data = box('One\nTwo', spacing: ParagraphSpacing.small);
      final html = htmlFromText(data);
      expect(html, contains('margin-bottom:0.25em'));
      expect(textFromHtml(html, const TextData())!.spacing, ParagraphSpacing.small);
      final plain = htmlFromText(box('One\nTwo', spacing: ParagraphSpacing.none));
      expect(plain, isNot(contains('margin')));
    });

    test('margins of other apps map to the nearest spacing; none keeps the box\'s', () {
      const style = TextData(spacing: ParagraphSpacing.large);
      expect(
        textFromHtml('<p style="margin-top:0pt;margin-bottom:6pt">a</p><p>b</p>', style)!.spacing,
        ParagraphSpacing.medium,
      );
      expect(textFromHtml('<p style="margin:0">a</p>', style)!.spacing, ParagraphSpacing.none);
      expect(textFromHtml('<p>a</p><p>b</p>', style)!.spacing, ParagraphSpacing.large);
      expect(
        textFromHtml('<li style="margin: 0 0 16px">a</li>', style)!.spacing,
        ParagraphSpacing.large,
      );
    });
  });
}
