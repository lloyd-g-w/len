import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/elements/text_edit_session.dart';
import 'package:len/ink/elements/text_flow_chains.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/selection_controller.dart';
import 'package:len/ink/selection/selection_surfaces.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/content_tools.dart';
import 'package:len/ink/undo_history.dart';
import 'package:len/ink/viewport.dart';

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

  group('rivals', rivalTests);
  group('paste', pasteTests);
  group('paste text', pasteTextTests);

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

/// Two devices that made a chain run on at once each stored a box
/// continuing it on the same page: the chain takes the older, and the next
/// time it flows the other goes.
void rivalTests() {
  late AppDatabase db;
  late ElementRepository elements;
  late FakePages pages;
  late TextFlowChains chains;

  setUp(() {
    db = AppDatabase.inMemory();
    final clock = FakeClock();
    elements = ElementRepository(db, deviceId: 'dev', clock: clock);
    final strokes = StrokeRepository(db, deviceId: 'dev', clock: clock);
    pages = FakePages(elements, strokes, ['p0', 'p1', 'p2']);
    chains = TextFlowChains(pages, clock: clock);
  });

  tearDown(() {
    pages.models.dispose();
    db.close();
  });

  SurfaceElement box(String id, String page, String text, {TextFlow? flow, int created = 1}) =>
      SurfaceElement(
        id: id,
        surfaceId: page,
        type: ElementType.text.name,
        rect: Rect.fromLTWH(40, page == 'p0' ? 600 : 48, 300, 30),
        z: 1,
        createdAt: created,
        data: TextData.rich(text: text).withFlow(flow).toJson(),
      );

  test('a rival continuation goes when the chain flows again', () {
    elements.save([
      box('h', 'p0', 'Alpha'),
      box('x', 'p1', 'Beta', flow: const TextFlow(from: 'h')),
      box('y', 'p1', 'Beta too', flow: const TextFlow(from: 'h'), created: 2),
    ]);
    final head = elements.allOn('p0').single;
    final rest = chains.continuationsOf('p0', 'h');
    expect([for (final r in rest) r.box.id], ['x']);
    pages.batch(() {
      final r = chains.reflow('p0', head, TextFlowChains.wholeOf(head, rest), rest);
      pages.modelOf('p0').commit(InkEdit(removedElements: [head], addedElements: [r.head]));
      chains.commit(r.edits);
    });
    // All fits on p0 now: neither stays on p1.
    expect(elements.allOn('p1'), isEmpty);
    expect(TextData.fromJson(elements.allOn('p0').single.data).text, 'Alpha\nBeta');
  });
}

/// The pages of [pages] one under another, for a selection reaching them.
class FakeSurfaces implements SelectionSurfaces {
  FakeSurfaces(this.pages);

  final FakePages pages;

  static const double pitch = 800 + FakePages.gap;

  @override
  ShiftedSurface? at(SurfaceModel from, Offset point) {
    final i = pages.ids.indexOf(from.surfaceId);
    final y = i * pitch + point.dy;
    final k = (y / pitch).floor();
    if (k < 0 || k >= pages.ids.length || y - k * pitch > FakePages.size.height) return null;
    return (model: pages.modelOf(pages.ids[k]), shift: Offset(0, (k - i) * pitch));
  }

  @override
  Iterable<ShiftedSurface> near(SurfaceModel from, Rect area) => const [];

  @override
  void batch(void Function() edits) => pages.batch(edits);
}

void pasteTests() {
  late AppDatabase db;
  late FakeClock clock;
  late ElementRepository elements;
  late FakePages pages;
  late TextFlowChains chains;
  late TextEditSession session;
  late SelectionController selection;

  setUp(() {
    db = AppDatabase.inMemory();
    clock = FakeClock();
    elements = ElementRepository(db, deviceId: 'dev', clock: clock);
    final strokes = StrokeRepository(db, deviceId: 'dev', clock: clock);
    pages = FakePages(elements, strokes, ['p0', 'p1', 'p2', 'p3']);
    chains = TextFlowChains(pages, clock: clock);
    session = TextEditSession(model: pages.modelOf('p0'), clock: clock)..flows = chains;
    selection =
        SelectionController(model: pages.modelOf('p0'), clipboard: InkClipboard(), clock: clock)
          ..flows = chains
          ..surfaces = FakeSurfaces(pages);
  });

  tearDown(() {
    selection.dispose();
    session.dispose();
    pages.models.dispose();
    db.close();
  });

  test('a duplicated chain starts where its first box was, however long the text', () {
    final text = [for (var i = 0; i < 60; i++) 'Line $i'].join('\n');
    session.create(const Offset(40, 600), style: const TextData(), width: 300);
    session.setData(TextData.rich(text: text));
    session.end();
    final head = elements.allOn('p0').single;
    selection.select(const [], [pages.modelOf('p0').elementById(head.id)!]);
    selection.duplicate();
    final heads = elements.allOn('p0');
    expect(heads, hasLength(2), reason: 'the copy begins on the same page');
    final copy = heads.firstWhere((e) => e.id != head.id);
    expect(copy.rect.top, closeTo(head.rect.top + 24, 0.01));
    final rest = chains.continuationsOf('p0', copy.id);
    expect(TextFlowChains.wholeOf(copy, rest).text, text);
  });

  test('a copied chain pastes as it was shown: its first box centred where pasted', () {
    final text = [for (var i = 0; i < 60; i++) 'Line $i'].join('\n');
    session.create(const Offset(40, 600), style: const TextData(), width: 300);
    session.setData(TextData.rich(text: text));
    session.end();
    final head = elements.allOn('p0').single;
    selection.select(const [], [pages.modelOf('p0').elementById(head.id)!]);
    selection.copy();
    selection.paste(const Offset(200, 300));
    final copy = elements.allOn('p0').firstWhere((e) => e.id != head.id);
    expect(copy.rect.top, closeTo(300 - head.rect.height / 2, 0.01));
    expect(TextFlowChains.wholeOf(copy, chains.continuationsOf('p0', copy.id)).text, text);
  });
}

void pasteTextTests() {
  late AppDatabase db;
  late ElementRepository elements;
  late FakePages pages;
  late ContentTools content;

  setUp(() {
    db = AppDatabase.inMemory();
    final clock = FakeClock();
    elements = ElementRepository(db, deviceId: 'dev', clock: clock);
    final strokes = StrokeRepository(db, deviceId: 'dev', clock: clock);
    pages = FakePages(elements, strokes, ['p0', 'p1']);
    content = ContentTools(
      model: pages.modelOf('p0'),
      viewport: ViewportController()..setSize(const Size(600, 800)),
      tools: ToolSettings(stylusOnly: true),
      live: LiveInk(),
      clipboard: InkClipboard(),
      clock: clock,
    )..flows = TextFlowChains(pages, clock: clock);
  });

  tearDown(() {
    content.dispose();
    pages.models.dispose();
    db.close();
  });

  test('a long pasted text begins on the page, not above it', () {
    final text = [for (var i = 0; i < 80; i++) 'Line $i'].join('\n');
    content.pasteText(TextData.rich(text: text));
    final head = elements.allOn('p0').single;
    expect(head.rect.top, greaterThanOrEqualTo(FlowPage.of('p0', FakePages.size).top));
    expect(elements.allOn('p1'), hasLength(1));
  });

  test('a short one is centred where it is pasted', () {
    content.pasteText(TextData.rich(text: 'Hello'));
    expect(elements.allOn('p0').single.rect.center.dy, closeTo(400, 0.01));
  });
}
