import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/text/rich_text_buffer.dart';
import 'package:len/domain/text/table_edits.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/elements/text_edit_session.dart';
import 'package:len/ink/elements/text_flow_chains.dart';

import 'data_test.dart' show FakeClock;
import 'text_flow_session_test.dart' show FakePages;

/// A table split over more than two pages shown one at a time stays one
/// table whichever page's part of it is edited (`TableFlow.carry`).
void main() {
  late AppDatabase db;
  late ElementRepository elements;
  late FakePages pages;
  late TextFlowChains chains;
  late TextEditSession session;
  const ids = ['p0', 'p1', 'p2', 'p3'];

  setUp(() {
    db = AppDatabase.inMemory();
    final clock = FakeClock();
    elements = ElementRepository(db, deviceId: 'dev', clock: clock);
    final strokes = StrokeRepository(db, deviceId: 'dev', clock: clock);
    pages = FakePages(elements, strokes, ids, together: false);
    chains = TextFlowChains(pages, clock: clock);
    session = TextEditSession(model: pages.modelOf('p0'), clock: clock)..flows = chains;
    // "Intro" and a 40 × 2 table from low on p0: it goes on over p1, p2, p3.
    final b = RichTextBuffer(const TextData(text: 'Intro'));
    final t = b.insertTable(5, 40, 2, header: true);
    for (var k = 0; k < t.cells; k++) {
      b.setCell(t.line + k, 'cell $k', List.filled('cell $k'.length, SpanStyle.plain));
    }
    session.create(const Offset(40, 500), style: const TextData(), width: 300);
    session.setData(b.toData(const TextData()));
    session.end();
  });

  tearDown(() {
    session.dispose();
    pages.models.dispose();
    db.close();
  });

  TextData whole() {
    final head = elements.allOn('p0').single;
    return TextFlowChains.wholeOf(head, chains.continuationsOf('p0', head.id));
  }

  void editOn(String page, void Function(RichTextBuffer b) edit) {
    session.model = pages.modelOf(page);
    final box = elements.allOn(page).single;
    session.edit(box);
    final data = session.data;
    final b = RichTextBuffer(data);
    edit(b);
    session.setData(b.toData(data));
    session.end();
  }

  /// The tables of the whole chain: (columns, rows) each.
  List<(int, int)> tables() => [for (final t in TextTables.of(whole().paras)) (t.columns, t.rows)];

  test('the table goes on over every page', () {
    for (final p in ids.skip(1)) {
      final data = TextData.fromJson(elements.allOn(p).single.data);
      expect(data.paras.first.cell!.spec.continued, isTrue, reason: p);
    }
    expect(tables(), [(2, 40)]);
  });

  test('a column added on a middle page goes to every part; one undo step', () {
    editOn('p1', (b) => b.insertColumn(b.tables.first, 1));
    expect(tables(), [(3, 40)]);
    pages.models.undo();
    expect(tables(), [(2, 40)]);
    pages.models.redo();
    expect(tables(), [(3, 40)]);
  });

  test('a column removed on a middle page goes from every part', () {
    editOn('p1', (b) => b.removeColumn(b.tables.first, 0));
    expect(tables(), [(1, 40)]);
  });

  test('a column added on the last page goes back to every part', () {
    editOn('p3', (b) => b.insertColumn(b.tables.first, 0));
    expect(tables(), [(3, 40)]);
  });
}
