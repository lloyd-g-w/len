import 'package:flutter/foundation.dart';

import '../../../ink/elements/text_edit_session.dart';
import '../../../ink/surface_model.dart';
import '../../../ink/tools/curve_drawing.dart';

/// What the editor's undo/redo buttons and shortcuts act on: a single
/// surface (infinite canvas) or a whole paged notebook.
abstract interface class UndoTarget implements Listenable {
  bool get canUndo;
  bool get canRedo;
  void undo();
  void redo();
}

/// Undo for a single surface.
class SurfaceUndo implements UndoTarget {
  SurfaceUndo(this.model);

  final SurfaceModel model;

  /// Called after every undo and redo.
  VoidCallback? onStep;

  @override
  bool get canUndo => model.history.canUndo;

  @override
  bool get canRedo => model.history.canRedo;

  @override
  void undo() {
    model.undo();
    onStep?.call();
  }

  @override
  void redo() {
    model.redo();
    onStep?.call();
  }

  @override
  void addListener(VoidCallback listener) => model.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => model.removeListener(listener);
}

/// [base], except while a text box is edited in [text]: then undo and redo
/// step through the box's own history (what was typed and formatted), and
/// undo past its first state finishes the box and undoes [base]. Likewise
/// while a [curve] is drawn: undo and redo take back and put back its
/// anchors (and the curve whose first anchor was undone).
class EditingUndo extends ChangeNotifier implements UndoTarget {
  EditingUndo(this.base, this.text, {this.curve}) {
    base.addListener(notifyListeners);
    text.addListener(_onText);
    curve?.addListener(notifyListeners);
    _onText();
  }

  final UndoTarget base;
  final TextEditSession text;
  final CurveDrawing? curve;
  BoxHistory? _box;

  void _onText() {
    final box = text.isEditing ? text.boxHistory : null;
    if (!identical(box, _box)) {
      _box?.removeListener(notifyListeners);
      _box = box?..addListener(notifyListeners);
    }
    notifyListeners();
  }

  /// The box history while a box is edited.
  BoxHistory? get _editing => text.isEditing ? text.boxHistory : null;

  bool get _drawing => curve?.active ?? false;

  @override
  bool get canUndo =>
      _drawing || (_editing?.canUndo ?? false) || (text.isEditing && text.isEdited) || base.canUndo;

  @override
  bool get canRedo {
    if (_drawing) return curve!.canRedo;
    if (curve?.canRedo ?? false) return true;
    return text.isEditing ? (_editing?.canRedo ?? false) : base.canRedo;
  }

  @override
  void undo() {
    if (curve?.undo() ?? false) return;
    if (_editing?.undo() ?? false) return;
    text.end();
    curve?.forget();
    base.undo();
  }

  @override
  void redo() {
    if (curve?.redo() ?? false) return;
    if (_drawing) return;
    if (text.isEditing) {
      _editing?.redo();
    } else {
      curve?.forget();
      base.redo();
    }
  }

  @override
  void dispose() {
    base.removeListener(notifyListeners);
    curve?.removeListener(notifyListeners);
    text.removeListener(_onText);
    _box?.removeListener(notifyListeners);
    super.dispose();
  }
}
