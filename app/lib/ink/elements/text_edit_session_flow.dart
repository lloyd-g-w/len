part of 'text_edit_session.dart';

/// How the edited box flows across pages.
enum _Flow {
  /// It doesn't (an infinite canvas, a rotated box).
  none,

  /// The whole chain is edited in one field over the pages shown together
  /// (continuous flow): [TextEditSession.current] holds all of its text.
  whole,

  /// One box of a chain is edited on its own (pages shown one at a time);
  /// the chain flows again when it ends.
  alone,
}

/// The session's chains of boxes flowing across pages: opening a chain,
/// measuring and splitting the text, hiding and drawing the boxes edited
/// (storing them: `text_edit_session_commit.dart`).
extension _SessionFlow on TextEditSession {
  /// How a box like [element] on the session's page flows.
  _Flow _flowFor(SurfaceElement element) {
    final chains = flows;
    if (chains == null || !chains.canFlow(_model.surfaceId, element)) return _Flow.none;
    return chains.pages.offsetOf(_model.surfaceId, 1) != null ? _Flow.whole : _Flow.alone;
  }

  /// Opens the chain of [element] when it is edited as a whole (true),
  /// the caret at [caret] (an offset in [element]'s own text, e.g. the
  /// table cell tapped; null: the end of [element]'s part); otherwise only
  /// sets how [element] flows (false: edit it as a box).
  bool _editChain(SurfaceElement element, {int? caret}) {
    _flow = _flowFor(element);
    if (_flow == _Flow.none) return false;
    final chains = flows!;
    final head = chains.headOf(_model.surfaceId, element);
    if (head == null) return false; // A box whose chain broke: on its own now.
    final rest = chains.continuationsOf(head.pageId, head.box.id);
    if (_flow == _Flow.whole && head.pageId != _model.surfaceId) {
      chains.pages.activate(head.pageId); // Edited from its first page.
      _flow = _flowFor(element);
    }
    if (_flow != _Flow.whole || head.pageId != _model.surfaceId) {
      _flow = _Flow.alone;
      _rest = rest;
      _aloneHead = head;
      _aloneIndex = 1 + rest.indexWhere((r) => r.box.id == element.id);
      return false;
    }
    _rest = rest;
    final whole = TextFlowChains.wholeOf(head.box, rest);
    final start = _startOf(element.id, head.box, rest);
    startCaret = caret != null && start != null
        ? start + caret
        : _caretAt(element.id, head.box, rest);
    _original = head.box;
    _startWidth = head.box.rect.width;
    _edited = false;
    _hide(head.box, rest);
    _measure(head.box.copyWith(data: whole.toJson(head.box.data)));
    return true;
  }

  /// The end of box [id]'s text in the whole text of a chain (null: the
  /// first box, where the caret goes to the end of everything).
  static int? _caretAt(String id, SurfaceElement head, List<FlowBox> rest) {
    if (id == head.id) return null;
    var at = TextData.fromJson(head.data).text.length;
    for (final r in rest) {
      final part = TextData.fromJson(r.box.data);
      if (!(part.flow?.joined ?? false)) at++;
      at += part.text.length;
      if (r.box.id == id) return at;
    }
    return null;
  }

  /// Where box [id]'s text starts in the whole text of a chain (null:
  /// not in it). A part's text is the whole text's from there on (a
  /// table going on keeps its text, only its first cell's style differs).
  static int? _startOf(String id, SurfaceElement head, List<FlowBox> rest) {
    if (id == head.id) return 0;
    var at = TextData.fromJson(head.data).text.length;
    for (final r in rest) {
      final part = TextData.fromJson(r.box.data);
      if (!(part.flow?.joined ?? false)) at++;
      if (r.box.id == id) return at;
      at += part.text.length;
    }
    return null;
  }

  /// [element] as edited on its own: a box whose chain broke stands alone.
  SurfaceElement _alone(SurfaceElement element) {
    if (_flow == _Flow.none || _aloneHead != null) return element;
    if (TextFlowChains.flowOf(element) == null) return element;
    final data = TextData.fromJson(element.data).withFlow(null);
    return element.copyWith(data: data.toJson(element.data));
  }

  /// Hides the boxes of a chain while it is edited.
  void _hide(SurfaceElement head, List<FlowBox> rest) {
    _model.setHidden({head.id}, owner: this);
    _hiding.add(_model.surfaceId);
    final byPage = <String, Set<String>>{};
    for (final r in rest) {
      (byPage[r.pageId] ??= {}).add(r.box.id);
    }
    for (final e in byPage.entries) {
      flows!.pages.modelOf(e.key).setHidden(e.value, owner: this);
      _hiding.add(e.key);
    }
  }

  SurfaceModel _modelOf(String pageId) =>
      pageId == _model.surfaceId ? _model : flows!.pages.modelOf(pageId);

  void _unhide() {
    for (final page in _hiding) {
      _modelOf(page).setHidden(const {}, owner: this);
    }
    _hiding.clear();
  }

  /// Follows the stored box changed elsewhere (not typed in yet).
  void _follow(SurfaceElement stored) {
    if (_flow != _Flow.whole) {
      _current = _alone(stored);
      if (_flow == _Flow.alone && _aloneIndex == 0 && _aloneHead != null) {
        _aloneHead = (pageId: _aloneHead!.pageId, box: stored);
      }
      return;
    }
    final chains = flows!;
    _unhide();
    _rest = chains.continuationsOf(_model.surfaceId, stored.id);
    _hide(stored, _rest);
    final whole = TextFlowChains.wholeOf(stored, _rest);
    _measure(stored.copyWith(data: whole.toJson(stored.data)));
  }

  /// Makes [element] the edited box: as wide as its text (auto width) and
  /// as tall, split over the pages when the whole chain is edited.
  void _measure(SurfaceElement element) {
    final m = _measured(element);
    _current = m.element;
    _parts = m.parts;
    _frames = m.frames;
  }

  ({SurfaceElement element, List<FlowPart> parts, List<Rect>? frames}) _measured(
    SurfaceElement element,
  ) {
    final r = element.rect;
    var data = TextData.fromJson(element.data);
    var width = math.max(r.width, TextLayout.minWidth);
    TextBoxLayout layout;
    if (data.autoWidth) {
      layout = _layouts.of(data, double.infinity);
      width = TextLayout.naturalWidthOf(layout);
      // A box wider than the limit (edited zoomed in) is not wrapped by it.
      final limit = _startWidth > autoWidthLimit ? double.infinity : autoWidthLimit;
      if (width > limit) {
        // Grown to the limit: wrap there from now on.
        width = math.max(limit, TextLayout.minWidth);
        data = data.copyWith(autoWidth: false);
        element = element.copyWith(data: data.toJson(element.data));
        layout = _layouts.of(data, width);
      }
    } else {
      layout = _layouts.of(data, width);
    }
    // A right-to-left box grows to the left: its start edge stays put.
    final rtl = data.directions.first == TextDirection.rtl;
    final left = rtl && width != r.width ? r.right - width : r.left;
    final box = Rect.fromLTWH(left, r.top, width, layout.height);
    if (_flow != _Flow.whole) {
      return (element: element.copyWith(rect: box), parts: const [], frames: null);
    }
    final chains = flows!;
    final parts = chains.split(_model.surfaceId, box, layout);
    final head = Rect.fromLTWH(left, r.top, width, parts.first.height);
    return (
      element: element.copyWith(rect: head),
      parts: parts,
      frames: parts.length > 1 ? chains.frames(_model.surfaceId, head, parts) : null,
    );
  }

  /// The page breaks of the edited chain were its text [data].
  List<FlowBreak> _breaksFor(TextData data) {
    final current = _current;
    if (_flow != _Flow.whole || current == null) return const [];
    final m = _measured(current.copyWith(data: data.toJson(current.data)));
    final frames = m.frames;
    if (frames == null) return const [];
    // The field lays the whole text out as wide as the first box: a part on
    // a page of another width is as tall there as its text is at that width.
    final width = frames.first.width;
    double shown(int k) => frames[k].width == width
        ? frames[k].height
        : TextLayout.heightOf(m.parts[k].dataOf(data, from: '-'), width);
    return [
      for (var k = 1; k < m.parts.length; k++)
        (
          at: m.parts[k].start,
          gap: frames[k].top - frames[k - 1].top - shown(k - 1),
          soft: m.parts[k].joined,
        ),
    ];
  }

  /// Tells the pages what to draw in place of the boxes edited, for their
  /// other views.
  void _lift() {
    final current = _current;
    final lifted = <String, SurfaceElement>{};
    var shown = current;
    if (current != null && _flow == _Flow.whole && _parts.length > 1) {
      final whole = TextData.fromJson(current.data);
      shown = current.copyWith(data: _parts.first.dataOf(whole).toJson(current.data));
      for (final p in flows!.preview(_model.surfaceId, current, whole, _parts)) {
        lifted[p.pageId] = p.box;
      }
    }
    final head = shown;
    _model.setLifted(this, head == null ? null : (c) => ContentPainter.paint(c, const [], [head]));
    _model.liftedChanged(this);
    for (final page in {..._liftedPages, ...lifted.keys}) {
      final model = _modelOf(page);
      final box = lifted[page];
      model.setLifted(this, box == null ? null : (c) => ContentPainter.paint(c, const [], [box]));
      model.liftedChanged(this);
    }
    _liftedPages
      ..clear()
      ..addAll(lifted.keys);
  }
}
