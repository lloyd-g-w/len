import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../domain/surface_element.dart';
import '../../domain/text_data.dart';
import '../surface_model.dart';
import '../undo_history.dart';
import 'text_layout.dart';

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

  TextData get data => TextData.fromJson(_current?.data ?? const {});

  /// Starts a new, empty text box at world point [at] (its first line's
  /// middle), [width] world units wide, formatted like [style].
  void create(Offset at, {required double width, required TextData style}) {
    end();
    final data = style.copyWith(text: '');
    final height = TextLayout.heightOf(data, width);
    _current = SurfaceElement(
      id: clock.newId(),
      surfaceId: _model.surfaceId,
      type: ElementType.text.name,
      rect: Rect.fromLTWH(at.dx, at.dy - height / 2, width, height),
      z: _model.topZ + 1,
      createdAt: clock.nowMs(),
      data: data.toJson(),
    );
    notifyListeners();
  }

  /// Starts editing an existing text box.
  void edit(SurfaceElement element) {
    if (identical(element, _original)) return;
    end();
    _original = element;
    _current = element;
    _model.setHidden({element.id});
    notifyListeners();
  }

  /// Changes the edited text and/or formatting.
  void setData(TextData data) {
    final current = _current;
    if (current == null) return;
    _update(current.copyWith(data: data.toJson(current.data)));
  }

  /// Moves or resizes the box (its height always follows the text).
  void setRect(Rect rect) {
    final current = _current;
    if (current == null) return;
    _update(current.copyWith(rect: rect));
  }

  void _update(SurfaceElement element) {
    final r = element.rect;
    final width = math.max(r.width, TextLayout.minWidth);
    final height = TextLayout.heightOf(TextData.fromJson(element.data), width);
    _current = element.copyWith(rect: Rect.fromLTWH(r.left, r.top, width, height));
    notifyListeners();
  }

  /// Ends editing, committing any change as one undoable edit.
  void end() {
    final original = _original;
    final current = _current;
    if (current == null) return;
    _original = null;
    _current = null;
    final data = TextData.fromJson(current.data);
    final empty = data.text.trim().isEmpty;
    if (original == null) {
      if (!empty) _model.commit(InkEdit(addedElements: [current]));
    } else if (empty) {
      _model.commit(InkEdit(removedElements: [original]));
    } else if (!_same(original, current)) {
      _model.commit(InkEdit(removedElements: [original], addedElements: [current]));
    }
    _model.setHidden(const {});
    notifyListeners();
  }

  /// Abandons the session without storing anything.
  void discard() {
    if (_current == null) return;
    _original = null;
    _current = null;
    _model.setHidden(const {});
    notifyListeners();
  }

  static bool _same(SurfaceElement a, SurfaceElement b) =>
      a.rect == b.rect &&
      a.rotation == b.rotation &&
      TextData.fromJson(a.data) == TextData.fromJson(b.data);

  /// The edited element changed underneath (undo, sync): stop editing.
  void _onModelChanged() {
    final original = _original;
    if (original != null && !identical(_model.elementById(original.id), original)) discard();
  }

  @override
  void dispose() {
    _model.removeListener(_onModelChanged);
    super.dispose();
  }
}
