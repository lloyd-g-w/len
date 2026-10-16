import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/elements/text_edit_session.dart';
import 'package:len/ink/elements/text_flow_chains.dart';
import 'package:len/ink/elements/text_hit_test.dart';

import 'data_test.dart' show FakeClock;
import 'text_flow_session_test.dart' show FakePages;

/// Ticking a checklist item a page break splits: one item, one tick.
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
    pages = FakePages(elements, strokes, ['p0', 'p1', 'p2']);
    chains = TextFlowChains(pages, clock: clock);
    session = TextEditSession(model: pages.modelOf('p0'), clock: clock)..flows = chains;
  });

  tearDown(() {
    session.dispose();
    pages.models.dispose();
    db.close();
  });

  /// One long checklist item from near p0's bottom on into p1.
  ({SurfaceElement head, SurfaceElement next}) splitItem() {
    session.create(const Offset(40, 650), style: const TextData(), width: 200);
    session.setData(
      TextData.rich(
        text: List.filled(40, 'word').join(' '),
        paras: const [ParaStyle(list: ListKind.check)],
      ),
    );
    session.end();
    final head = elements.allOn('p0').single;
    final next = elements.allOn('p1').single;
    expect(TextFlowChains.flowOf(next)!.joined, isTrue);
    return (head: head, next: next);
  }

  test('ticking it ticks its part on the next page too, one undo step', () {
    final (:head, :next) = splitItem();
    TextHitTest.toggleChecked(pages.modelOf('p0'), head, 0, flows: chains);
    bool ticked(String page) =>
        TextData.fromJson(elements.allOn(page).single.data).paras[0].checked;
    expect(ticked('p0'), isTrue);
    expect(ticked('p1'), isTrue);
    expect(TextFlowChains.flowOf(elements.allOn('p1').single)!.from, head.id);
    pages.models.undo();
    expect(ticked('p0'), isFalse);
    expect(ticked('p1'), isFalse);
    expect(elements.allOn('p1').single.id, next.id);
  });
}
