import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/document/page_models.dart';
import 'package:len/ink/elements/text_edit_session.dart';
import 'package:len/ink/elements/text_flow_chains.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/ink/elements/text_layout_cache.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/selection_controller.dart';
import 'package:len/ink/surface_model.dart';

import 'data_test.dart' show FakeClock;

/// Pages of [size] in a column (continuous flow) or one at a time.
class FakePages implements TextFlowPages {
  FakePages(this.elements, this.strokes, this.ids, {this.together = true});

  final ElementRepository elements;
  final StrokeRepository strokes;
  final List<String> ids;
  bool together;
  static const size = Size(600, 800);
  static const gap = 28.0;
  final PageModels models = PageModels();
  final List<String> added = [];
  void Function(String pageId)? onActivate;

  @override
  List<FlowPage>? pagesFrom(String pageId) {
    final i = ids.indexOf(pageId);
    return i == -1 ? null : [for (final id in ids.skip(i)) FlowPage.of(id, size)];
  }

  @override
  String? pageBefore(String pageId) {
    final i = ids.indexOf(pageId);
    return i > 0 ? ids[i - 1] : null;
  }

  @override
  Offset? offsetOf(String pageId, int k) => together ? Offset(0, k * (size.height + gap)) : null;

  @override
  List<SurfaceElement> elementsOn(String pageId) => elements.allOn(pageId);

  @override
  SurfaceModel modelOf(String pageId) =>
      models.peek(pageId) ??
      models.acquire(
        pageId,
        () =>
            SurfaceModel(surfaceId: pageId, repository: strokes, elementRepository: elements)
              ..ensureLoaded(Offset.zero & size),
      );

  @override
  String addPage() {
    final id = 'added${added.length}';
    ids.add(id);
    added.add(id);
    return id;
  }

  @override
  void batch(void Function() edits) => models.group(edits);

  @override
  void activate(String pageId) => onActivate?.call(pageId);
}

/// [n] numbered lines.
String lines(int n, [String word = 'Line']) => [for (var i = 0; i < n; i++) '$word $i'].join('\n');

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late ElementRepository elements;
  late FakePages pages;
  late TextFlowChains chains;
  late TextEditSession session;
  final line = TextLayout.heightOf(const TextData(text: 'x'), 300);

  setUp(() {
    db = AppDatabase.inMemory();
    clock = FakeClock();
    elements = ElementRepository(db, deviceId: 'dev', clock: clock);
    final strokes = StrokeRepository(db, deviceId: 'dev', clock: clock);
    pages = FakePages(elements, strokes, ['p0', 'p1', 'p2']);
    chains = TextFlowChains(pages, clock: clock);
    session = TextEditSession(model: pages.modelOf('p0'), clock: clock)..flows = chains;
    pages.onActivate = (id) => session.model = pages.modelOf(id);
  });

  tearDown(() {
    session.dispose();
    pages.models.dispose();
    db.close();
  });

  List<SurfaceElement> textOn(String page) => elements.allOn(page);

  /// The chain starting with the only box on page p0, as one text.
  TextData stored() {
    final head = textOn('p0').single;
    return TextFlowChains.wholeOf(head, chains.continuationsOf('p0', head.id));
  }

  /// Types [text] into a new box at [top] on p0 and finishes it.
  void typeBox(String text, {double top = 600, double width = 300}) {
    session.create(Offset(40, top), style: const TextData(), width: width);
    session.setData(TextData.rich(text: text));
    session.end();
  }

  test('a box reaching the bottom margin continues on the next page', () {
    typeBox(lines(12));
    final head = textOn('p0').single;
    final next = textOn('p1').single;
    final room = FlowPage.of('p0', FakePages.size).bottom - 600;
    expect(head.rect.bottom, lessThanOrEqualTo(600 + room + 0.01));
    expect(TextData.fromJson(head.data).lineCount, (room / line).floor());
    expect(TextChainsCheck.flowOf(next)!.from, head.id);
    expect(next.rect.top, FlowPage.of('p1', FakePages.size).top);
    expect(next.rect.left, head.rect.left);
    expect(next.rect.width, head.rect.width);
    expect(stored().text, lines(12));
    expect(textOn('p2'), isEmpty);
  });

  test('the whole chain is one undo step; so is redo', () {
    typeBox(lines(40));
    expect(textOn('p2'), isNotEmpty);
    pages.models.undo();
    expect(textOn('p0') + textOn('p1') + textOn('p2'), isEmpty);
    pages.models.redo();
    expect(stored().text, lines(40));
  });

  test('pages are added at the end for text that runs on', () {
    typeBox(lines(70));
    expect(pages.added, isNotEmpty);
    expect(stored().text, lines(70));
    final last = pages.ids.last;
    expect(TextChainsCheck.flowOf(textOn(last).single), isNotNull);
  });

  test('editing a continuation edits the whole chain from its first page', () {
    typeBox(lines(12));
    final next = textOn('p1').single;
    session.model = pages.modelOf('p1');
    session.edit(next);
    expect(session.model.surfaceId, 'p0');
    expect(session.data.text, lines(12));
    expect(session.startCaret, lines(12).length);
    expect(session.frames, hasLength(2));
    expect(pages.modelOf('p1').isHidden(next.id), isTrue);
    // The field leaves room over the page edge, from part to part.
    final breaks = session.breaksFor(session.data);
    expect(breaks.single.gap, closeTo(session.frames[1].top - session.frames[0].bottom, 1e-9));
    expect(breaks.single.soft, isFalse);

    // Deleting lines pulls the text back onto the first page.
    session.setData(TextData.rich(text: lines(3)));
    session.end();
    expect(pages.modelOf('p1').isHidden(next.id), isFalse);
    expect(textOn('p1'), isEmpty);
    expect(TextData.fromJson(textOn('p0').single.data).text, lines(3));
  });

  test('moving the first box reflows the chain', () {
    typeBox(lines(6), top: 100);
    expect(textOn('p1'), isEmpty);
    session.edit(textOn('p0').single);
    session.setRect(session.current!.rect.shift(const Offset(0, 560)));
    session.end();
    expect(textOn('p1'), hasLength(1));
    expect(stored().text, lines(6));
  });

  test('emptying the box deletes the chain', () {
    typeBox(lines(20));
    session.edit(textOn('p0').single);
    session.setData(const TextData());
    session.end();
    expect(textOn('p0') + textOn('p1') + textOn('p2'), isEmpty);
  });

  test('a page shown alone edits its box alone; the chain flows when it ends', () {
    typeBox(lines(12));
    pages.together = false;
    final next = textOn('p1').single;
    session.model = pages.modelOf('p1');
    session.edit(next);
    expect(session.model.surfaceId, 'p1');
    final part = TextData.fromJson(next.data);
    session.setData(TextData.rich(text: '${part.text}\nmore').withFlow(part.flow));
    session.end();
    expect(stored().text, '${lines(12)}\nmore');
  });

  test('a deleted page breaks the chain: the rest stands alone', () {
    typeBox(lines(40));
    final third = textOn('p2').single;
    pages.ids.remove('p1');
    expect(chains.continuationsOf('p0', textOn('p0').single.id), isEmpty);
    expect(chains.headOf('p2', third), isNull);
    // Edited, it is a box of its own.
    session.model = pages.modelOf('p2');
    session.edit(third);
    expect(session.data.flow, isNull);
  });

  test('typing on keeps one layout per keystroke', () {
    session.create(const Offset(40, 600), style: const TextData(), width: 300);
    // Measuring and splitting read the same layout: the field's breaks for
    // a text come from the layout the session then keeps.
    for (var i = 1; i < 30; i++) {
      final data = TextData.rich(text: lines(i));
      final before = TextLayoutCache.debugLayouts;
      session.breaksFor(data);
      session.setData(data);
      expect(TextLayoutCache.debugLayouts - before, 1);
    }
    expect(session.frames.length, greaterThan(1));
    session.end();
  });

  group('lasso', () {
    late SelectionController selection;

    setUp(() {
      selection = SelectionController(
        model: pages.modelOf('p0'),
        clipboard: InkClipboard(),
        clock: clock,
      )..flows = chains;
    });

    tearDown(() => selection.dispose());

    /// The only box on [page] as its model holds it.
    SurfaceElement live(String page) => pages.modelOf(page).elementById(textOn(page).single.id)!;

    test('moving the first box carries its chain; one undo step', () {
      typeBox(lines(12));
      selection.select(const [], [live('p0')]);
      selection.nudge(const Offset(0, -480));
      expect(textOn('p1'), isEmpty, reason: 'it all fits on the first page now');
      expect(stored().text, lines(12));
      expect(selection.elements.single.rect.height, textOn('p0').single.rect.height);
      // The selection holds the box as laid out: moving it back flows again.
      selection.nudge(const Offset(0, 480));
      expect(textOn('p1'), hasLength(1));
      expect(stored().text, lines(12));
      pages.models.undo();
      expect(textOn('p1'), isEmpty);
      pages.models.undo();
      expect(textOn('p1'), hasLength(1));
      expect(stored().text, lines(12));
    });

    test('deleting the first box deletes the chain; undo brings it back', () {
      typeBox(lines(40));
      selection.select(const [], [live('p0')]);
      selection.delete();
      expect(textOn('p0') + textOn('p1') + textOn('p2'), isEmpty);
      pages.models.undo();
      expect(stored().text, lines(40));
    });

    test('a continuation is not selected on its own; a broken one is', () {
      typeBox(lines(12));
      final next = live('p1');
      final there = SelectionController(
        model: pages.modelOf('p1'),
        clipboard: InkClipboard(),
        clock: clock,
      )..flows = chains;
      addTearDown(there.dispose);
      there.select(const [], [next]);
      expect(there.isEmpty, isTrue);
      pages.ids.remove('p0');
      there.select(const [], [next]);
      expect(there.elements, hasLength(1));
    });

    test('copying the first box copies the whole text', () {
      typeBox(lines(12));
      selection
        ..select(const [], [live('p0')])
        ..copy();
      expect(TextData.fromJson(selection.clipboard.elements.single.data).text, lines(12));
    });

    test('dragging the first box into another editor carries the whole text', () {
      typeBox(lines(12));
      selection.select(const [], [live('p0')]);
      final carried = selection.carried;
      expect(TextData.fromJson(carried.elements.single.data).text, lines(12));
      expect(carried.bounds.height, closeTo(carried.elements.single.rect.height, 1));
    });

    test('rotating the first box gathers the whole text into it', () {
      typeBox(lines(12));
      final head = live('p0');
      selection
        ..select(const [], [head])
        ..replaceElements([head.copyWith(rotation: 0.3)]);
      expect(textOn('p1'), isEmpty);
      expect(TextData.fromJson(textOn('p0').single.data).text, lines(12));
    });
  });
}

/// Reads a stored box's flow.
abstract final class TextChainsCheck {
  static TextFlow? flowOf(SurfaceElement e) => TextFlowChains.flowOf(e);
}
