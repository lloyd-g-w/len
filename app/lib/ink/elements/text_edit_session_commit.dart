part of 'text_edit_session.dart';

/// Storing what a [TextEditSession] edited, as one undoable edit: a box
/// created, changed or emptied (deleted), or a chain flowing across pages;
/// then forgetting it.
extension _SessionCommit on TextEditSession {
  /// Stores [current], the edit of [original] (null: a new box) whose text
  /// is [data] ([empty]: blank).
  void _commit(
    SurfaceElement? original,
    SurfaceElement current,
    TextData data, {
    required bool empty,
  }) {
    switch (_flow) {
      case _Flow.none:
        if (original == null) {
          if (!empty) _model.commit(InkEdit(addedElements: [current]));
        } else if (empty) {
          _model.commit(InkEdit(removedElements: [original]));
        } else if (!_same(original, current)) {
          _model.commit(InkEdit(removedElements: [original], addedElements: [current]));
        }
      case _Flow.whole:
        _commitWhole(original, current, data);
      case _Flow.alone:
        _commitAlone(original, current, data);
    }
  }

  static bool _same(SurfaceElement a, SurfaceElement b) =>
      a.rect == b.rect &&
      a.rotation == b.rotation &&
      TextData.fromJson(a.data) == TextData.fromJson(b.data);

  void _reset() {
    _flow = _Flow.none;
    _rest = const [];
    _aloneHead = null;
    _aloneIndex = 0;
    _typed = null;
    _parts = const [];
    _frames = null;
    startCaret = null;
  }

  /// Stores the chain edited as a whole.
  void _commitWhole(SurfaceElement? original, SurfaceElement current, TextData data) {
    if (original != null && !_edited) return;
    final chains = flows!;
    if (data.isBlank) {
      if (original == null) return;
      chains.pages.batch(() {
        _model.commit(InkEdit(removedElements: [original]));
        chains.commit(chains.removing(_model.surfaceId, original.id, _rest));
      });
      return;
    }
    chains.pages.batch(() {
      final r = chains.reflow(_model.surfaceId, current, data, _rest);
      _model.commit(InkEdit(removedElements: [?original], addedElements: [r.head]));
      chains.commit(r.edits);
    });
  }

  /// Stores a box edited on its own: its chain (or the box, which may now
  /// reach the next page) flows again.
  void _commitAlone(SurfaceElement? original, SurfaceElement current, TextData data) {
    if (original != null && !_edited) return;
    final chains = flows!;
    final head = _aloneHead;
    final headPage = head?.pageId ?? _model.surfaceId;
    final parts = [
      if (head != null) ...[
        TextData.fromJson(head.box.data),
        for (final r in _rest) TextData.fromJson(r.box.data),
      ] else
        data,
    ];
    final empty = data.isBlank;
    if (head != null) {
      if (!empty) {
        _carryFirstLine(parts, data);
        final typed = _typed;
        parts[_aloneIndex] = typed != null && typed.text == data.text
            ? data.withFormatting(paras: typed.paras)
            : data;
        TableFlow.carry(parts, _aloneIndex);
      } else {
        final gone = parts.removeAt(_aloneIndex);
        // What went on with the emptied part's last paragraph now goes on
        // with what that paragraph went on with (as deleting the part from
        // the whole text would).
        final next = _aloneIndex < parts.length ? parts[_aloneIndex] : null;
        final flow = next?.flow;
        if (_aloneIndex > 0 && flow != null && flow.joined && !(gone.flow?.joined ?? false)) {
          parts[_aloneIndex] = next!.withFlow(
            TextFlow(from: flow.from, numbers: flow.numbers, direction: flow.direction),
          );
        }
      }
    }
    final stored = head == null || _aloneIndex == 0 ? original : head.box;
    final first = head == null || _aloneIndex == 0 ? current : head.box;
    final whole = parts.isEmpty ? const TextData() : TextFlow.join(parts);
    chains.pages.batch(() {
      if (whole.isBlank) {
        if (stored == null) return;
        _modelOf(headPage).commit(InkEdit(removedElements: [stored]));
        chains.commit(chains.removing(headPage, stored.id, _rest));
        return;
      }
      final r = chains.reflow(headPage, first, whole, _rest);
      _modelOf(headPage).commit(InkEdit(removedElements: [?stored], addedElements: [r.head]));
      chains.commit(r.edits);
    });
  }

  /// A part edited on its own whose first line goes on with the page
  /// before ([TextFlow.joined]) shares that paragraph with the parts
  /// before it, whose style wins when the chain is joined: a style changed
  /// there ([data], a heading, a tick) goes back to them.
  void _carryFirstLine(List<TextData> parts, TextData data) {
    final was = parts[_aloneIndex];
    final style = data.paras.first;
    if (_aloneIndex == 0 || !(was.flow?.joined ?? false) || style == was.paras.first) return;
    for (var k = _aloneIndex - 1; k >= 0; k--) {
      final part = parts[k];
      parts[k] = part.withFormatting(paras: [...part.paras.take(part.lineCount - 1), style]);
      // A part all of that paragraph's: it goes on from the part before.
      if (part.lineCount > 1 || !(part.flow?.joined ?? false)) break;
    }
  }
}
