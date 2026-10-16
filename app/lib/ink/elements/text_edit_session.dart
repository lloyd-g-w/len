import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../domain/surface_element.dart';
import '../../domain/text/text_data.dart';
import '../render/content_painter.dart';
import '../surface_model.dart';
import '../undo_history.dart';
import 'text_flow_chains.dart';
import 'text_layout.dart';
import 'text_layout_cache.dart';

part 'text_edit_session_flow.dart';

/// The edited box's own history (its editor keeps it): what the editor's
/// undo and redo act on while a box is edited.
abstract interface class BoxHistory implements Listenable {
  bool get canUndo;
  bool get canRedo;

  /// Steps back; false when there is nothing to undo.
  bool undo();

  /// Steps forward; false when there is nothing to redo.
  bool redo();
}

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

/// The text box being edited on a surface, if any.
///
/// While editing, the element is hidden from the committed layer and an
/// on-canvas text field shows [current] instead. Nothing is stored until
/// [end], which commits the whole editing session as one undoable edit
/// (creating, changing or — when emptied — deleting the text box).
///
/// On the pages of a notebook ([flows]) a box reaching the bottom margin
/// continues on the next page (see [TextFlowChains]): with the pages shown
/// together the whole chain is edited as one text ([current] is its first
/// box holding all of it, shown in [frames]); otherwise the box tapped is
/// edited alone and the chain flows again when editing ends. Either way it
/// is one undoable edit.
class TextEditSession extends ChangeNotifier {
  TextEditSession({required this._model, this.clock = const Clock()}) {
    _model.addListener(_onModelChanged);
  }

  final Clock clock;

  SurfaceModel _model;
  SurfaceModel get model => _model;
  set model(SurfaceModel value) {
    if (identical(value, _model)) return;
    end();
    _model.removeListener(_onModelChanged);
    _model = value..addListener(_onModelChanged);
  }

  /// Chains of boxes flowing across pages (paged notebooks); null on a
  /// canvas, where boxes grow.
  TextFlowChains? flows;

  SurfaceElement? _original;
  SurfaceElement? _current;

  /// The stored element being edited; null while creating a new one.
  SurfaceElement? get original => _original;

  /// The element as currently edited.
  SurfaceElement? get current => _current;

  bool get isEditing => _current != null;

  /// The box finished last (not emptied): typing on goes under it.
  ({String surfaceId, Rect rect})? lastBox;

  /// The history of the box being typed in, set by its editor.
  BoxHistory? boxHistory;

  /// The editor's undo and redo (the box's history first, then past its
  /// start the page's), for the box's own Ctrl+Z / Ctrl+Shift+Z; null:
  /// the box's history alone.
  VoidCallback? undo, redo;

  /// Where the caret starts (model offset) in the box just opened; null:
  /// at the end.
  int? startCaret;

  TextData get data => TextData.fromJson(_current?.data ?? const {});

  final TextLayoutCache _layouts = TextLayoutCache();
  _Flow _flow = _Flow.none;

  /// The continuations of the chain edited, as stored when editing began.
  List<FlowBox> _rest = const [];

  /// Editing one box of a chain alone: its first box (null: [current] is
  /// one) and which box is edited (0: the first).
  FlowBox? _aloneHead;
  int _aloneIndex = 0;

  /// The edited text's parts on successive pages, and where they are shown
  /// (page coordinates of [model]).
  List<FlowPart> _parts = const [];
  List<Rect>? _frames;

  /// Pages whose boxes this session hides (their parts are edited here).
  final Set<String> _hiding = {};

  /// Pages other than [model]'s told what to draw in place of their boxes.
  final Set<String> _liftedPages = {};

  /// Where the edited text is shown, page by page (one rect unless the whole
  /// chain is edited over several pages).
  List<Rect> get frames => _frames ?? [?_current?.rect];

  /// Where the edited text continues on the next pages if it is [data]
  /// (for the editing field, which shows the whole chain): none unless the
  /// whole chain is edited over pages shown together.
  List<FlowBreak> breaksFor(TextData data) => _breaksFor(data);

  /// Whether world point [world] (page coordinates of [model]) is on the
  /// text being edited, also where it continues on other pages.
  bool covers(Offset world, {double slop = 0}) =>
      frames.any((f) => f.inflate(slop).contains(world));

  /// Which of [frames] model offset [offset] of the edited text is in.
  int frameOf(int offset) {
    var k = 0;
    while (k + 1 < _parts.length && _parts[k + 1].start <= offset) {
      k++;
    }
    return k;
  }

  /// Starts a new text box at world point [at] (its first line's middle),
  /// formatted like [style], holding [text] (empty by default). Without a
  /// [width] the box is as wide as its text (growing up to
  /// [autoWidthLimit], then wrapping).
  void create(Offset at, {required TextData style, double? width, String text = ''}) {
    _end(notify: false);
    // A box started by typing holds what was typed: an edit to undo.
    _edited = text.isNotEmpty;
    _startWidth = 0;
    final data = style.copyWith(text: text, autoWidth: width == null).withFlow(null);
    final w = width ?? _layouts.naturalWidth(data);
    final height = _layouts.of(data, w).height;
    final element = SurfaceElement(
      id: clock.newId(),
      surfaceId: _model.surfaceId,
      type: ElementType.text.name,
      rect: Rect.fromLTWH(at.dx, at.dy - height / 2, w, height),
      z: _model.topZ + 1,
      createdAt: clock.nowMs(),
      data: data.toJson(),
    );
    _flow = _flowFor(element);
    _measure(element);
    notifyListeners();
  }

  /// Widest an auto-width box grows (world units) before it starts to
  /// wrap at that width, e.g. up to the edge of the screen or page. A box
  /// already wider when editing starts (seen zoomed in) grows freely.
  double autoWidthLimit = double.infinity;

  /// Width of the edited box when editing started.
  double _startWidth = 0;

  /// Starts editing an existing text box (of a chain flowing across pages:
  /// the whole chain, see the class doc).
  void edit(SurfaceElement element) {
    if (identical(element, _original)) return;
    if (_current != null && _rest.any((r) => r.box.id == element.id)) return;
    _end(notify: false);
    if (_editChain(element)) {
      notifyListeners();
      return;
    }
    _original = element;
    _current = _alone(element);
    _startWidth = element.rect.width;
    _edited = false;
    _model.setHidden({element.id}, owner: this);
    _hiding.add(_model.surfaceId);
    if (_flow == _Flow.whole) _measure(_current!);
    notifyListeners();
  }

  /// Changes the edited text and/or formatting.
  void setData(TextData data) {
    final current = _current;
    if (current == null) return;
    _update(current.copyWith(data: data.toJson(current.data)));
  }

  /// Moves the box.
  void setRect(Rect rect) {
    final current = _current;
    if (current == null) return;
    _update(current.copyWith(rect: rect));
  }

  /// Sets the box's left edge and width: from now on it wraps at that
  /// width (auto width ends).
  void setWidth(double left, double width) {
    final current = _current;
    if (current == null) return;
    final r = current.rect;
    final data = TextData.fromJson(current.data).copyWith(autoWidth: false);
    _update(
      current.copyWith(
        rect: Rect.fromLTWH(left, r.top, math.max(width, TextLayout.minWidth), r.height),
        data: data.toJson(current.data),
      ),
    );
  }

  /// Whether the user changed the box in this session (until then it
  /// follows changes made elsewhere).
  bool get isEdited => _edited;
  bool _edited = false;

  void _update(SurfaceElement element) {
    _edited = true;
    _measure(element);
    notifyListeners();
  }

  /// Ends editing, committing any change as one undoable edit.
  void end() => _end(notify: true);

  /// Ends editing; [notify] is off when another box starts straight away
  /// (listeners see one change, not a moment without a box).
  void _end({required bool notify}) {
    final original = _original;
    final current = _current;
    if (current == null) return;
    _original = null;
    _current = null;
    final data = TextData.fromJson(current.data);
    final empty = data.text.trim().isEmpty;
    lastBox = empty || _parts.length > 1
        ? null
        : (surfaceId: current.surfaceId, rect: current.rect);
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
    _unhide();
    _reset();
    if (notify) notifyListeners();
  }

  /// Abandons the session without storing anything.
  void discard() {
    if (_current == null) return;
    _original = null;
    _current = null;
    _unhide();
    _reset();
    notifyListeners();
  }

  void _reset() {
    _flow = _Flow.none;
    _rest = const [];
    _aloneHead = null;
    _aloneIndex = 0;
    _parts = const [];
    _frames = null;
    startCaret = null;
  }

  static bool _same(SurfaceElement a, SurfaceElement b) =>
      a.rect == b.rect &&
      a.rotation == b.rotation &&
      TextData.fromJson(a.data) == TextData.fromJson(b.data);

  /// The surface changed underneath. If the edited box was removed (undo,
  /// sync), stop editing; if it was reloaded or changed by sync, keep
  /// editing it — the user's pending changes win, an untouched box follows.
  void _onModelChanged() {
    final original = _original;
    if (original == null) return;
    final stored = _model.elementById(original.id);
    if (identical(stored, original)) return;
    if (stored == null) {
      // While a reload is reading, the box is merely not back yet.
      if (!_model.isLoading) discard();
      return;
    }
    _original = stored;
    if (!_edited) {
      _follow(stored);
      notifyListeners();
    }
  }

  @override
  /// Also tells the surfaces what to draw in place of the boxes being
  /// edited, for other views of them (split view): the text as typed.
  @override
  void notifyListeners() {
    _lift();
    super.notifyListeners();
  }

  @override
  void dispose() {
    _model.setLifted(this, null);
    _model.removeListener(_onModelChanged);
    _layouts.dispose();
    super.dispose();
  }
}
