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

/// A table split between pages shown one at a time stays one table
/// whichever page's part of it is edited (UX_AUDIT R26-13).
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
    pages = FakePages(elements, strokes, ['p0', 'p1', 'p2'], together: false);
    chains = TextFlowChains(pages, clock: clock);
    session = TextEditSession(model: pages.modelOf('p0'), clock: clock)..flows = chains;
    // "Intro" and a 12 × 2 table with a header from low on p0: it goes on on p1.
    final b = RichTextBuffer(const TextData(text: 'Intro'));
    final t = b.insertTable(5, 12, 2, header: true);
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

  List<String> row(TextData data, TextTable t, int r) {
    final lines = data.text.split('\n');
    return [for (var c = 0; c < t.columns; c++) lines[t.lineOf(r, c)]];
  }

  /// Edits the box on [page] alone, [edit] changing its text's buffer.
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

  test('the chain is split inside the table', () {
    final next = TextData.fromJson(elements.allOn('p1').single.data);
    expect(next.paras.first.cell!.spec.continued, isTrue);
  });

  test('a column added on the next page is added to the whole table', () {
    editOn('p1', (b) => b.insertColumn(b.tables.first, 1));
    final data = whole();
    final t = TextTables.of(data.paras).single;
    expect(t.columns, 3);
    expect(t.rows, 12);
    expect(t.spec.header, isTrue);
    expect(row(data, t, 0), ['cell 0', '', 'cell 1']);
    expect(row(data, t, 11), ['cell 22', '', 'cell 23']);
  });

  test('a column removed on the first page goes from the whole table', () {
    editOn('p0', (b) => b.removeColumn(b.tables.first, 0));
    final data = whole();
    final t = TextTables.of(data.paras).single;
    expect(t.columns, 1);
    expect(t.rows, 12);
    expect(row(data, t, 11), ['cell 23']);
  });

  test('columns added and removed again come out as they were', () {
    editOn('p1', (b) {
      var t = b.insertColumn(b.tables.first, 0);
      t = b.insertColumn(t, 3);
      t = b.removeColumn(t, 0)!;
      b.removeColumn(t, 1);
    });
    final data = whole();
    final t = TextTables.of(data.paras).single;
    expect(t.columns, 2);
    expect(row(data, t, 0), ['cell 0', '']);
    expect(row(data, t, 11), ['cell 22', '']);
  });

  test('widths and the header set on the next page are the whole table\'s', () {
    editOn('p1', (b) {
      final t = b.tables.first;
      b.setSpec(t, t.spec.copyWith(widths: [0.3, 0.7], header: false));
    });
    final t = TextTables.of(whole().paras).single;
    expect(t.spec.widths, [0.3, 0.7]);
    expect(t.spec.header, isFalse);
  });

  test('typing outside the table on the first page keeps it one table', () {
    editOn('p0', (b) {
      b.replace(0, 0, 'New ', SpanStyle.plain);
      b.repairTables(); // As the editor does: a line after the table ending the box.
    });
    final data = whole();
    expect(TextTables.of(data.paras).single.rows, 12);
    expect(data.text.startsWith('New Intro\n'), isTrue);
  });
}
