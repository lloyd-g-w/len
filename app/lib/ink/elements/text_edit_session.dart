import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../domain/surface_element.dart';
import '../../domain/text/paragraph_direction.dart';
import '../../domain/text/text_data.dart';
import '../render/content_painter.dart';
import '../surface_model.dart';
import '../undo_history.dart';
import 'text_layout.dart';

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

/// The text box being edited on a surface, if any.
///
/// While editing, the element is hidden from the committed layer and an
/// on-canvas text field shows [current] instead. Nothing is stored until
/// [end], which commits the whole editing session as one undoable edit
/// (creating, changing or — when emptied — deleting the text box).
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

  TextData get data => TextData.fromJson(_current?.data ?? const {});

  /// Starts a new text box at world point [at] (its first line's middle),
  /// formatted like [style], holding [text] (empty by default). Without a
  /// [width] the box is as wide as its text (growing up to
  /// [autoWidthLimit], then wrapping).
  void create(Offset at, {required TextData style, double? width, String text = ''}) {
    _end(notify: false);
    _edited = false;
    _startWidth = 0;
    final data = style.copyWith(text: text, autoWidth: width == null);
    final w = width ?? TextLayout.naturalWidth(data);
    final height = TextLayout.heightOf(data, w);
    _current = SurfaceElement(
      id: clock.newId(),
      surfaceId: _model.surfaceId,
      type: ElementType.text.name,
      rect: Rect.fromLTWH(at.dx, at.dy - height / 2, w, height),
      z: _model.topZ + 1,
      createdAt: clock.nowMs(),
      data: data.toJson(),
    );
    notifyListeners();
  }

  /// Widest an auto-width box grows (world units) before it starts to
  /// wrap at that width, e.g. up to the edge of the screen or page. A box
  /// already wider when editing starts (seen zoomed in) grows freely.
  double autoWidthLimit = double.infinity;

  /// Width of the edited box when editing started.
  double _startWidth = 0;

  /// Starts editing an existing text box.
  void edit(SurfaceElement element) {
    if (identical(element, _original)) return;
    _end(notify: false);
    _original = element;
    _current = element;
    _startWidth = element.rect.width;
    _edited = false;
    _model.setHidden({element.id}, owner: this);
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
    final r = element.rect;
    var data = TextData.fromJson(element.data);
    var width = math.max(r.width, TextLayout.minWidth);
    if (data.autoWidth) {
      width = TextLayout.naturalWidth(data);
      // A box wider than the limit (edited zoomed in) is not wrapped by it.
      final limit = _startWidth > autoWidthLimit ? double.infinity : autoWidthLimit;
      if (width > limit) {
        // Grown to the limit: wrap there from now on.
        width = math.max(limit, TextLayout.minWidth);
        data = data.copyWith(autoWidth: false);
        element = element.copyWith(data: data.toJson(element.data));
      }
    }
    final height = TextLayout.heightOf(data, width);
    // A right-to-left box grows to the left: its start edge stays put.
    final rtl = ParagraphDirection.baseOf(data.text) == TextDirection.rtl;
    final left = rtl && width != r.width ? r.right - width : r.left;
    _current = element.copyWith(rect: Rect.fromLTWH(left, r.top, width, height));
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
    lastBox = empty ? null : (surfaceId: current.surfaceId, rect: current.rect);
    if (original == null) {
      if (!empty) _model.commit(InkEdit(addedElements: [current]));
    } else if (empty) {
      _model.commit(InkEdit(removedElements: [original]));
    } else if (!_same(original, current)) {
      _model.commit(InkEdit(removedElements: [original], addedElements: [current]));
    }
    _model.setHidden(const {}, owner: this);
    if (notify) notifyListeners();
  }

  /// Abandons the session without storing anything.
  void discard() {
    if (_current == null) return;
    _original = null;
    _current = null;
    _model.setHidden(const {}, owner: this);
    notifyListeners();
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
      _current = stored;
      notifyListeners();
    }
  }

  @override
  /// Also tells the surface what to draw in place of the box being
  /// edited, for other views of it (split view): the box as typed.
  @override
  void notifyListeners() {
    _model.setLifted(this, _current == null ? null : _paintLifted);
    _model.liftedChanged(this);
    super.notifyListeners();
  }

  void _paintLifted(Canvas canvas) {
    final current = _current;
    if (current != null) ContentPainter.paint(canvas, const [], [current]);
  }

  @override
  void dispose() {
    _model.setLifted(this, null);
    _model.removeListener(_onModelChanged);
    super.dispose();
  }
}
