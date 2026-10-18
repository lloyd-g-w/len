import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/rich_text_buffer.dart';
import 'package:len/domain/text/table_edits.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/elements/element_renderer.dart';
import 'package:len/ink/elements/shown_text_layout.dart';
import 'package:len/ink/elements/text_edit_session.dart';
import 'package:len/ink/elements/text_flow_chains.dart';
import 'package:len/ink/elements/text_layout.dart';

import 'data_test.dart' show FakeClock;
import 'text_flow_session_test.dart' show FakePages;

/// A table row taller than a page is cut at the page's end, drawn clipped
/// there, and kept whole in the text (UX_AUDIT R26-14).
void main() {
  late AppDatabase db;
  late ElementRepository elements;
  late FakePages pages;
  late TextFlowChains chains;
  late TextEditSession session;

  setUp(() {
    db = AppDatabase.inMemory();
    final clock = FakeClock();
    elements = ElementRepository(db, deviceId: 'dev', clock: clock);
    final strokes = StrokeRepository(db, deviceId: 'dev', clock: clock);
    pages = FakePages(elements, strokes, ['p0', 'p1', 'p2', 'p3']);
    chains = TextFlowChains(pages, clock: clock);
    session = TextEditSession(model: pages.modelOf('p0'), clock: clock)..flows = chains;
    pages.onActivate = (id) => session.model = pages.modelOf(id);
  });

  tearDown(() {
    session.dispose();
    pages.models.dispose();
    db.close();
  });

  final long = List.filled(700, 'word').join(' ');

  /// "Intro", then a 3 × 2 table whose second row holds [long] in its
  /// first cell, then "After".
  TextData text() {
    final b = RichTextBuffer(const TextData(text: 'Intro\nAfter'));
    final t = b.insertTable(5, 3, 2);
    for (var k = 0; k < t.cells; k++) {
      final s = k == 2 ? long : 'cell $k';
      b.setCell(t.line + k, s, List.filled(s.length, SpanStyle.plain));
    }
    return b.toData(const TextData());
  }

  List<SurfaceElement> boxes() => [for (final p in pages.ids) ...elements.allOn(p)];

  TextData whole() {
    final head = elements.allOn('p0').single;
    return TextFlowChains.wholeOf(head, chains.continuationsOf('p0', head.id));
  }

  test('the row makes a part of its own, cut at the page\'s end', () {
    final data = text();
    expect(TextLayout.heightOf(data, 300), greaterThan(2 * FakePages.size.height));
    session.create(const Offset(40, 100), style: const TextData(), width: 300);
    session.setData(data);
    session.end();
    final all = boxes();
    for (final b in all) {
      final page = FlowPage.of(b.surfaceId, FakePages.size);
      expect(b.rect.bottom, lessThanOrEqualTo(page.bottom + 0.01), reason: b.surfaceId);
    }
    expect(whole(), data, reason: 'the text keeps the row whole');
    final cut = all.firstWhere((b) => TextData.fromJson(b.data).text.contains(long));
    expect(cut.surfaceId, 'p1');
    final shown = ShownTextLayout.of(TextData.fromJson(cut.data), cut.rect.size);
    addTearDown(shown.dispose);
    expect(shown.clipped, isNotNull);
    // What follows the row goes on on the page after.
    final next = elements.allOn('p2').single;
    expect(TextData.fromJson(next.data).text, contains('After'));
  });

  test('editing the chain as a whole shows the row whole, the next part after it', () {
    session.create(const Offset(40, 100), style: const TextData(), width: 300);
    session.setData(text());
    session.end();
    session.edit(elements.allOn('p0').single);
    final breaks = session.breaksFor(session.data);
    expect(breaks, hasLength(2));
    expect(breaks.every((b) => b.gap >= 0), isTrue);
    session.end();
  });

  test('drawn, the cut row stays inside its frame', () async {
    session.create(const Offset(40, 100), style: const TextData(), width: 300);
    session.setData(text());
    session.end();
    final cut = elements.allOn('p1').single;
    final e = cut.copyWith(rect: cut.rect.shift(-cut.rect.topLeft + const Offset(10, 10)));
    final recorder = ui.PictureRecorder();
    ElementRenderer.draw(Canvas(recorder), e);
    final w = 400, h = (e.rect.bottom + 200).ceil();
    final image = await recorder.endRecording().toImage(w, h);
    final bytes = (await image.toByteData())!;
    var below = 0, inside = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (bytes.getUint8((y * w + x) * 4 + 3) == 0) continue;
        if (y >= e.rect.bottom.ceil()) {
          below++;
        } else {
          inside++;
        }
      }
    }
    expect(inside, greaterThan(0));
    expect(below, 0);
  });
}
