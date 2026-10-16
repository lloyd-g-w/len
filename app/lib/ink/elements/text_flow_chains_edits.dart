part of 'text_flow_chains.dart';

/// Storing chains: flowing one again into per-page edits, deleting one,
/// committing.
mixin _ChainEdits {
  TextFlowPages get pages;
  Clock get clock;
  bool canFlow(String pageId, SurfaceElement box);
  List<FlowBox> continuationsOf(String pageId, String headId);
  List<FlowBox> allAfter(String pageId, String headId);
  FlowBox? headOf(String pageId, SurfaceElement box);
  List<FlowPart> split(String pageId, Rect rect, TextBoxLayout layout);

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
      var page = TextFlowChains.pageOf(after, k);
      final id = page.id ?? pages.addPage();
      page = FlowPage(id: id, size: page.size, top: page.top, bottom: page.bottom);
      final was = _reuse(old, k - 1, id, kept);
      final box = SurfaceElement(
        id: was?.id ?? clock.newId(),
        surfaceId: id,
        type: ElementType.text.name,
        rect: TextFlowChains._frameOn(after.first, page, r, parts[k].height),
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
        if (TextFlowChains.flowOf(e)?.from != from || taken.contains(e.id)) continue;
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
        final head = TextFlowChains.flowOf(e) == null
            ? (pageId: pageId, box: e)
            : headOf(pageId, e);
        if (head != null) heads[head.box.id] ??= head.pageId;
      }
    }
    for (final MapEntry(key: id, value: pageId) in heads.entries) {
      final head = pages.elementsOn(pageId).where((e) => e.id == id).firstOrNull;
      if (head == null || !canFlow(pageId, head)) continue;
      final rest = continuationsOf(pageId, id);
      final r = reflow(pageId, head, TextFlowChains.wholeOf(head, rest), rest);
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
