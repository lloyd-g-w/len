import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/elements/text_edit_session.dart';
import 'package:len/ink/elements/text_flow_chains.dart';

import 'data_test.dart' show FakeClock;
import 'text_flow_session_test.dart' show FakePages;

/// A box of a chain edited on its own (pages shown one at a time).
void main() {
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
    pages = FakePages(elements, strokes, ['p0', 'p1', 'p2'], together: false);
    chains = TextFlowChains(pages, clock: clock);
    session = TextEditSession(model: pages.modelOf('p0'), clock: clock)..flows = chains;
  });

  tearDown(() {
    session.dispose();
    pages.models.dispose();
    db.close();
  });

  SurfaceElement box(String id, String page, String text, {TextFlow? flow}) => SurfaceElement(
    id: id,
    surfaceId: page,
    type: ElementType.text.name,
    rect: Rect.fromLTWH(40, page == 'p0' ? 600 : 48, 300, 30),
    z: 1,
    createdAt: 1,
    data: TextData.rich(text: text).withFlow(flow).toJson(),
  );

  TextData whole() {
    final head = elements.allOn('p0').single;
    return TextFlowChains.wholeOf(head, chains.continuationsOf('p0', head.id));
  }

  test('emptying a part between pages keeps the paragraphs either side apart', () {
    elements.save([
      box('h', 'p0', 'Alpha'),
      box('c1', 'p1', 'Beta', flow: const TextFlow(from: 'h')),
      box('c2', 'p2', 'gamma', flow: const TextFlow(from: 'c1', joined: true)),
    ]);
    expect(whole().text, 'Alpha\nBetagamma');
    session.model = pages.modelOf('p1');
    final c1 = elements.allOn('p1').single;
    session.edit(c1);
    session.setData(TextData.rich(text: '').withFlow(TextData.fromJson(c1.data).flow));
    session.end();
    // As deleting "Beta" from the whole text does.
    expect(whole().text, 'Alpha\ngamma');
  });

  test('emptying a part that went on with the page before joins what follows to it', () {
    elements.save([
      box('h', 'p0', 'Alpha'),
      box('c1', 'p1', 'beta', flow: const TextFlow(from: 'h', joined: true)),
      box('c2', 'p2', 'gamma', flow: const TextFlow(from: 'c1', joined: true)),
    ]);
    session.model = pages.modelOf('p1');
    final c1 = elements.allOn('p1').single;
    session.edit(c1);
    session.setData(TextData.rich(text: '').withFlow(TextData.fromJson(c1.data).flow));
    session.end();
    expect(whole().text, 'Alphagamma');
  });
}
