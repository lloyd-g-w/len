import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/elements/text_edit_session.dart';
import 'package:len/ink/elements/text_flow_chains.dart';
import 'package:len/ink/elements/text_layout.dart';

import 'data_test.dart' show FakeClock;
import 'text_flow_session_test.dart' show FakePages;

/// A chain running from a wide page (a landscape slide) onto narrower ones
/// (portrait paper): its continuations fit their pages.
void main() {
  late AppDatabase db;
  late ElementRepository elements;
  late FakePages pages;
  late TextFlowChains chains;
  late TextEditSession session;
  const wide = Size(1000, 600);

  setUp(() {
    db = AppDatabase.inMemory();
    final clock = FakeClock();
    elements = ElementRepository(db, deviceId: 'dev', clock: clock);
    final strokes = StrokeRepository(db, deviceId: 'dev', clock: clock);
    pages = FakePages(elements, strokes, ['p0', 'p1', 'p2'])..sizes['p0'] = wide;
    chains = TextFlowChains(pages, clock: clock);
    session = TextEditSession(model: pages.modelOf('p0'), clock: clock)..flows = chains;
    pages.onActivate = (id) => session.model = pages.modelOf(id);
  });

  tearDown(() {
    session.dispose();
    pages.models.dispose();
    db.close();
  });

  final text = List.filled(400, 'word').join(' ');

  /// Types [text] into a box 800 wide on the wide page and finishes it.
  List<SurfaceElement> typeChain() {
    session.create(const Offset(100, 300), style: const TextData(), width: 800);
    session.setData(TextData.rich(text: text));
    session.end();
    return [for (final id in pages.ids) ...elements.allOn(id)];
  }

  void expectFitting(List<SurfaceElement> boxes) {
    expect(boxes.length, greaterThan(2));
    expect(boxes.first.rect.width, 800);
    final margin = FlowPage.marginOf(FakePages.size);
    for (final box in boxes.skip(1)) {
      final page = FlowPage.of(box.surfaceId, pages.sizeOf(box.surfaceId));
      expect(box.rect.left, greaterThanOrEqualTo(margin), reason: '${box.rect}');
      expect(box.rect.right, lessThanOrEqualTo(page.size.width - margin), reason: '${box.rect}');
      // Laid out at its own width, it is as tall as stored, within the page.
      final data = TextData.fromJson(box.data);
      expect(box.rect.height, closeTo(TextLayout.heightOf(data, box.rect.width), 0.01));
      expect(box.rect.bottom, lessThanOrEqualTo(page.bottom + 0.01));
    }
    expect(TextFlow.join([for (final b in boxes) TextData.fromJson(b.data)]).text, text);
  }

  test('pages shown together: continuations as wide as the narrower page allows', () {
    expectFitting(typeChain());
  });

  test('one page at a time too', () {
    pages.together = false;
    expectFitting(typeChain());
  });

  test('a chain edited whole on pages together keeps fitting', () {
    typeChain();
    final head = elements.allOn('p0').single;
    session.edit(head);
    expect(session.frames.length, greaterThan(2));
    expect(session.frames[1].width, lessThan(800));
    session.setData(TextData.rich(text: 'More. $text'));
    session.end();
    final boxes = [for (final id in pages.ids) ...elements.allOn(id)];
    expect(TextFlow.join([for (final b in boxes) TextData.fromJson(b.data)]).text, 'More. $text');
    expect(boxes.skip(1).every((b) => b.rect.right <= FakePages.size.width), isTrue);
  });

  test('a page as wide keeps the head width and line', () {
    pages.sizes.clear();
    final boxes = typeChain();
    for (final box in boxes.skip(1)) {
      expect(box.rect.left, 100);
      expect(box.rect.width, 800);
    }
  });
}
