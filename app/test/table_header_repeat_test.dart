import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/text/rich_text_buffer.dart';
import 'package:len/domain/text/table_edits.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/domain/text/text_record.dart';
import 'package:len/ink/elements/shown_text_layout.dart';
import 'package:len/ink/elements/text_edit_session.dart';
import 'package:len/ink/elements/text_flow_chains.dart';
import 'package:len/ink/elements/text_layout.dart';

import 'data_test.dart' show FakeClock;
import 'text_flow_session_test.dart' show FakePages;

/// A table's header row is repeated on the pages it goes on to, for
/// display only (UX_AUDIT R26-15).
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

  /// "Intro" and a [rows] × 2 table ("Name", "Qty" heading it when
  /// [header]), from low on p0.
  TextData store(int rows, {bool header = true}) {
    final b = RichTextBuffer(const TextData(text: 'Intro'));
    final t = b.insertTable(5, rows, 2, header: header);
    for (var k = 0; k < t.cells; k++) {
      final s = k == 0 ? 'Name' : (k == 1 ? 'Qty' : 'cell $k');
      b.setCell(t.line + k, s, List.filled(s.length, SpanStyle.plain));
    }
    final data = b.toData(const TextData());
    session.create(const Offset(40, 500), style: const TextData(), width: 300);
    session.setData(data);
    session.end();
    return data;
  }

  TextData whole() {
    final head = elements.allOn('p0').single;
    return TextFlowChains.wholeOf(head, chains.continuationsOf('p0', head.id));
  }

  test('a box going on with a table with a header repeats the header, not in its text', () {
    final data = store(30);
    final next = elements.allOn('p1').single;
    final part = TextData.fromJson(next.data);
    expect([for (final c in part.flow!.header) c.text], ['Name', 'Qty']);
    expect(part.text, isNot(contains('Name')));
    expect(TextTables.plainText(part.text, part.paras), isNot(contains('Qty')));
    expect(whole(), data);
    // Laid out with the header above its rows, within its frame and page.
    final layout = TextLayout.layout(part, next.rect.width);
    addTearDown(layout.dispose);
    final t = layout.tables.first;
    expect(t.band, greaterThan(0));
    expect([for (final c in t.headerCells) c.data.text], ['Name', 'Qty']);
    expect(layout.height, closeTo(next.rect.height, 0.5));
    final shown = ShownTextLayout.of(part, next.rect.size);
    addTearDown(shown.dispose);
    expect(shown.clipped, isNull, reason: 'no row is cut');
    expect(next.rect.bottom, lessThanOrEqualTo(FlowPage.of('p1', FakePages.size).bottom + 0.01));
    // The first row's cells start below the header.
    final row = layout.rows.first;
    expect(t.textOrigin(row.rect, 0, 0).dy, greaterThan(row.rect.top + t.band));
    // Every page after the first repeats it.
    final last = TextData.fromJson(elements.allOn('p2').single.data);
    expect([for (final c in last.flow!.header) c.text], ['Name', 'Qty']);
  });

  test('a table without a header repeats nothing', () {
    store(30, header: false);
    final part = TextData.fromJson(elements.allOn('p1').single.data);
    expect(part.flow!.header, isEmpty);
    expect(part.flow!.toJson().containsKey('header'), isFalse);
  });

  test('the header is stored with the flow and read strictly', () {
    store(30);
    final json = elements.allOn('p1').single.data;
    final read = TextRecord.parse(json);
    expect(read, TextData.fromJson(json));
    expect(read.flow!.header.first.text, 'Name');
    final flow = {...(json['flow']! as Map<String, Object?>)};
    flow['header'] = [
      {'text': 'Name', 'spans': 'x'},
    ];
    expect(() => TextRecord.parse({...json, 'flow': flow}), throwsFormatException);
  });

  test('drawn, the repeated header is bold text above the rows', () async {
    store(30);
    final next = elements.allOn('p1').single;
    final e = next.copyWith(rect: next.rect.shift(-next.rect.topLeft + const Offset(4, 4)));
    final part = TextData.fromJson(e.data);
    final layout = TextLayout.layout(part, e.rect.width);
    addTearDown(layout.dispose);
    final band = layout.tables.first.band;
    final recorder = ui.PictureRecorder();
    layout.paint(Canvas(recorder), e.rect.topLeft);
    final image = await recorder.endRecording().toImage(320, 120);
    final bytes = (await image.toByteData())!;
    var ink = 0;
    for (var y = 6; y < (4 + band - 2).floor(); y++) {
      for (var x = 10; x < 60; x++) {
        if (bytes.getUint8((y * 320 + x) * 4 + 3) > 0) ink++;
      }
    }
    expect(ink, greaterThan(20), reason: '"Name" in the header band');
  });
}
