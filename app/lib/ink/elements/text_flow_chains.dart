import 'dart:math' as math;
import 'dart:ui';

import '../../core/clock.dart';
import '../../domain/surface_element.dart';
import '../../domain/text/text_data.dart';
import '../undo_history.dart';
import 'text_flow_layout.dart';
import 'text_flow_pages.dart';
import 'text_layout.dart';

export 'text_flow_layout.dart';
export 'text_flow_pages.dart';

/// A text box of a chain and the page it is on.
typedef FlowBox = ({String pageId, SurfaceElement box});

/// Chains of text boxes flowing across the pages of a notebook.
///
/// A text box (not rotated) on a page whose text reaches the page's bottom
/// margin continues in a box at the top of the next page, and so on (a page
/// is added after the last when needed). The first box (the head) holds
/// the chain's position, width and box style; each continuation names the
/// box before it ([TextFlow.from]) and sits on the very next page. A
/// continuation whose box before is gone, or not on the page before (pages
/// deleted or reordered), stands alone: it keeps its text and is drawn as
/// it was; the chain before it simply ends.
class TextFlowChains {
  TextFlowChains(this.pages, {this.clock = const Clock()});

  final TextFlowPages pages;
  final Clock clock;

  /// Most boxes a chain reaches.
  static const int maxParts = 500;

  /// The flow of text box [e], if it continues another.
  static TextFlow? flowOf(SurfaceElement e) =>
      e.knownType == ElementType.text ? TextFlow.fromJson(e.data['flow']) : null;

  /// Whether text box [box] on [pageId] flows across pages: a text box, not
  /// rotated, on a page.
  bool canFlow(String pageId, SurfaceElement box) =>
      box.knownType == ElementType.text && box.rotation == 0 && pages.pagesFrom(pageId) != null;

  /// The boxes continuing box [headId] (on page [pageId]) on the pages
  /// after it, in order.
  List<FlowBox> continuationsOf(String pageId, String headId) {
    final after = pages.pagesFrom(pageId);
    if (after == null) return const [];
    final out = <FlowBox>[];
    var previous = headId;
    for (final page in after.skip(1).take(maxParts)) {
      final id = page.id;
      if (id == null) break;
      final next = _continuing(id, previous);
      if (next == null) break;
      out.add((pageId: id, box: next));
      previous = next.id;
    }
    return out;
  }

  /// Every box on the pages after [pageId] whose chain leads back to box
  /// [headId] there: its continuations, and boxes continuing them that
  /// the chain did not take (see [_continuing]) with what runs on from
  /// those, in page order.
  List<FlowBox> allAfter(String pageId, String headId) {
    final after = pages.pagesFrom(pageId);
    if (after == null) return const [];
    final out = <FlowBox>[];
    var from = {headId};
    for (final page in after.skip(1).take(maxParts)) {
      final id = page.id;
      if (id == null) break;
      final next = [
        for (final e in pages.elementsOn(id))
          if (from.contains(flowOf(e)?.from)) e,
      ];
      if (next.isEmpty) break;
      out.addAll([for (final e in next) (pageId: id, box: e)]);
      from = {for (final e in next) e.id};
    }
    return out;
  }

  /// The box on [pageId] continuing box [from]: of several (two devices
  /// reflowing at once), the oldest.
  SurfaceElement? _continuing(String pageId, String from) {
    SurfaceElement? best;
    for (final e in pages.elementsOn(pageId)) {
      if (flowOf(e)?.from != from) continue;
      if (best == null ||
          e.createdAt < best.createdAt ||
          (e.createdAt == best.createdAt && e.id.compareTo(best.id) < 0)) {
        best = e;
      }
    }
    return best;
  }

  /// The first box of the chain [box] (on [pageId]) belongs to: [box]
  /// itself when it continues no box, null when the chain is broken (it
  /// stands alone).
  FlowBox? headOf(String pageId, SurfaceElement box) {
    var page = pageId;
    var current = box;
    for (var i = 0; i < maxParts; i++) {
      final flow = flowOf(current);
      if (flow == null) {
        if (identical(current, box)) return (pageId: page, box: box);
        final rest = continuationsOf(page, current.id);
        return rest.any((r) => r.box.id == box.id) ? (pageId: page, box: current) : null;
      }
      final before = pages.pageBefore(page);
      if (before == null) return null;
      final previous = pages.elementsOn(before).where((e) => e.id == flow.from).firstOrNull;
      if (previous == null) return null;
      page = before;
      current = previous;
    }
    return null;
  }

  /// The text of [head] and its continuations [rest] as one.
  static TextData wholeOf(SurfaceElement head, List<FlowBox> rest) => TextFlow.join([
    TextData.fromJson(head.data),
    for (final r in rest) TextData.fromJson(r.box.data),
  ]);

  /// The parts of [layout] (the whole text of a chain whose head is at
  /// [rect] on [pageId]) on that page and the pages after it.
  List<FlowPart> split(String pageId, Rect rect, TextBoxLayout layout) {
    final after = pages.pagesFrom(pageId);
    if (after == null) {
      return [FlowPart(start: 0, end: layout.data.text.length, height: layout.height)];
    }
    double room(int k) =>
        k == 0 ? after.first.bottom - rect.top : after[math.min(k, after.length - 1)].room;
    double width(int k) =>
        k == 0 ? rect.width : columnOn(after.first, pageOf(after, k), rect).width;
    return TextFlowLayout.split(layout, room, width: width);
  }

  /// The page part [k] of a chain starting on [pageId] goes to ([after]
  /// is [TextFlowPages.pagesFrom]); pages not added yet are like the last.
  static FlowPage pageOf(List<FlowPage> after, int k) {
    if (k < after.length) return after[k];
    final last = after.last;
    return FlowPage(id: null, size: last.size, top: last.top, bottom: last.bottom);
  }

  /// Where the [parts] of a chain whose head is at [rect] on [pageId] are
  /// shown, in that page's coordinates; null when the view does not show
  /// the pages together.
  List<Rect>? frames(String pageId, Rect rect, List<FlowPart> parts) {
    final after = pages.pagesFrom(pageId);
    if (after == null) return null;
    final out = [Rect.fromLTWH(rect.left, rect.top, rect.width, parts.first.height)];
    for (var k = 1; k < parts.length; k++) {
      final offset = pages.offsetOf(pageId, k);
      if (offset == null) return null;
      final page = pageOf(after, k);
      out.add(_frameOn(after.first, page, rect, parts[k].height).shift(offset));
    }
    return out;
  }

  /// Where a continuation of a head at [rect] on page [head] lies across
  /// [page]: lined up with it when pages are centred one under another,
  /// and as wide; on a narrower page where that would stick out, as wide
  /// as fits between its side margins ([FlowPage.marginOf]) at most.
  static ({double left, double width}) columnOn(FlowPage head, FlowPage page, Rect rect) {
    final left = rect.left + (page.size.width - head.size.width) / 2;
    final width = page.size.width;
    if (width >= head.size.width || (left >= 0 && left + rect.width <= width)) {
      return (left: left, width: rect.width);
    }
    final margin = FlowPage.marginOf(page.size);
    final fits = math.max(math.min(rect.width, width - 2 * margin), TextLayout.minWidth);
    return (left: left.clamp(margin, math.max(margin, width - margin - fits)), width: fits);
  }

  /// A continuation [height] tall on [page] of a head at [rect] on [head].
  static Rect _frameOn(FlowPage head, FlowPage page, Rect rect, double height) {
    final column = columnOn(head, page, rect);
    return Rect.fromLTWH(column.left, page.top, column.width, height);
  }

  /// The continuations [parts] of [whole] make after [head] (on [pageId]),
  /// on the pages there are: for drawing them while the chain is edited
  /// (their ids are not the stored ones).
  List<FlowBox> preview(String pageId, SurfaceElement head, TextData whole, List<FlowPart> parts) {
    final after = pages.pagesFrom(pageId);
    if (after == null) return const [];
    final r = head.rect;
    return [
      for (var k = 1; k < parts.length && k < after.length; k++)
        (
          pageId: after[k].id!,
          box: SurfaceElement(
            id: '${head.id}~$k',
            surfaceId: after[k].id!,
            type: ElementType.text.name,
            rect: _frameOn(after.first, after[k], r, parts[k].height),
            z: head.z,
            createdAt: head.createdAt,
            data: parts[k].dataOf(whole, from: head.id).toJson(),
          ),
        ),
    ];
  }

  /// The edits that store [whole] as the text of the chain whose first box
  /// is [head] (on [pageId]; its data is replaced) in place of its old
  /// continuations [old]: the head as laid out (its part of the text, its
  /// height) and each page's edit of continuations. Adds pages as needed:
  /// call within [TextFlowPages.batch].
  ({SurfaceElement head, Map<String, InkEdit> edits}) reflow(
    String pageId,
    SurfaceElement head,
    TextData whole,
    List<FlowBox> old, {
    TextBoxLayout? layout,
  }) {
    final after = pages.pagesFrom(pageId)!;
    final laid = layout ?? TextLayout.layout(whole, head.rect.width);
    final parts = split(pageId, head.rect, laid);
    if (layout == null) laid.dispose();
    final r = head.rect;
    final first = head.copyWith(
      rect: Rect.fromLTWH(r.left, r.top, r.width, parts.first.height),
      data: parts.first.dataOf(whole).toJson(head.data),
    );
    final edits = <String, _Edits>{};
    _Edits on(String id) => edits[id] ??= _Edits();
    final kept = <String>{};
    var previous = head.id;
    for (var k = 1; k < parts.length; k++) {
      var page = pageOf(after, k);
      final id = page.id ?? pages.addPage();
      page = FlowPage(id: id, size: page.size, top: page.top, bottom: page.bottom);
      final was = _reuse(old, k - 1, id, kept);
      final box = SurfaceElement(
        id: was?.id ?? clock.newId(),
        surfaceId: id,
        type: ElementType.text.name,
        rect: _frameOn(after.first, page, r, parts[k].height),
        z: was?.z ?? _topZ(id) + 1,
        createdAt: was?.createdAt ?? clock.nowMs(),
        data: parts[k].dataOf(whole, from: previous).toJson(was?.data ?? const {}),
      );
      previous = box.id;
      if (was != null) {
        kept.add(was.id);
        if (_same(was, box)) continue;
        on(id).removed.add(was);
      }
      on(id).added.add(box);
    }
    for (final o in old) {
      if (!kept.contains(o.box.id)) on(o.pageId).removed.add(o.box);
    }
    for (final r in _rivals(pageId, head.id, old)) {
      on(r.pageId).removed.add(r.box);
    }
    return (head: first, edits: {for (final e in edits.entries) e.key: e.value.build()});
  }

  /// Boxes continuing a box of the chain of [headId] (on [pageId]; its
  /// continuations [old]) on the very next page that the chain did not
  /// take (see [_continuing]): two devices made it run on at once. They
  /// hold a copy of its text, so they go when it flows again, with what
  /// runs on from them.
  List<FlowBox> _rivals(String pageId, String headId, List<FlowBox> old) {
    final taken = {for (final o in old) o.box.id};
    final out = <FlowBox>[];
    for (final (:page, id: from) in [
      (page: pageId, id: headId),
      for (final o in old) (page: o.pageId, id: o.box.id),
    ]) {
      final next = pages.pagesFrom(page)?.skip(1).firstOrNull?.id;
      if (next == null) continue;
      for (final e in pages.elementsOn(next)) {
        if (flowOf(e)?.from != from || taken.contains(e.id)) continue;
        out
          ..add((pageId: next, box: e))
          ..addAll(allAfter(next, e.id));
      }
    }
    return out;
  }

  /// The old continuation to keep for part [index] on page [pageId]: the
  /// one that was there.
  static SurfaceElement? _reuse(List<FlowBox> old, int index, String pageId, Set<String> kept) {
    if (index < old.length && old[index].pageId == pageId && !kept.contains(old[index].box.id)) {
      return old[index].box;
    }
    return old
        .where((o) => o.pageId == pageId && !kept.contains(o.box.id))
        .map((o) => o.box)
        .firstOrNull;
  }

  double _topZ(String pageId) {
    var top = 0.0;
    for (final e in pages.elementsOn(pageId)) {
      if (e.z > top) top = e.z;
    }
    return top;
  }

  static bool _same(SurfaceElement a, SurfaceElement b) =>
      a.rect == b.rect &&
      a.rotation == b.rotation &&
      a.z == b.z &&
      TextData.fromJson(a.data) == TextData.fromJson(b.data);

  /// The edits removing what follows head [headId] (on [pageId]) when it
  /// is deleted: its continuations [rest] and every box whose chain leads
  /// to it ([allAfter]: a rival left by two devices too).
  Map<String, InkEdit> removing(String pageId, String headId, [List<FlowBox> rest = const []]) {
    final edits = <String, Map<String, SurfaceElement>>{};
    for (final r in [...rest, ...allAfter(pageId, headId)]) {
      (edits[r.pageId] ??= {})[r.box.id] = r.box;
    }
    return {
      for (final e in edits.entries) e.key: InkEdit(removedElements: [...e.value.values]),
    };
  }

  /// Flows again every chain with a box on [pageIds] (pages that changed
  /// shape: a part may now stick out past a page's bottom, or room opened
  /// up), committing the edits. Call within [TextFlowPages.batch].
  void reflowOn(Iterable<String> pageIds) {
    final heads = <String, String>{}; // Head id → its page.
    for (final pageId in pageIds) {
      for (final e in pages.elementsOn(pageId)) {
        if (e.knownType != ElementType.text) continue;
        final head = flowOf(e) == null ? (pageId: pageId, box: e) : headOf(pageId, e);
        if (head != null) heads[head.box.id] ??= head.pageId;
      }
    }
    for (final MapEntry(key: id, value: pageId) in heads.entries) {
      final head = pages.elementsOn(pageId).where((e) => e.id == id).firstOrNull;
      if (head == null || !canFlow(pageId, head)) continue;
      final rest = continuationsOf(pageId, id);
      final r = reflow(pageId, head, wholeOf(head, rest), rest);
      if (!_same(head, r.head)) {
        pages.modelOf(pageId).commit(InkEdit(removedElements: [head], addedElements: [r.head]));
      }
      commit(r.edits);
    }
  }

  /// Commits each page's edit of [edits] to its model.
  void commit(Map<String, InkEdit> edits) {
    for (final e in edits.entries) {
      pages.modelOf(e.key).commit(e.value);
    }
  }
}

class _Edits {
  final List<SurfaceElement> added = [];
  final List<SurfaceElement> removed = [];

  InkEdit build() => InkEdit(addedElements: added, removedElements: removed);
}
