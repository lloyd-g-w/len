import '../domain/stroke.dart';

/// One undoable change to a surface: strokes added and/or removed.
class InkEdit {
  InkEdit({List<Stroke>? added, List<Stroke>? removed})
      : added = added ?? const [],
        removed = removed ?? const [];

  final List<Stroke> added;
  final List<Stroke> removed;

  InkEdit get inverse => InkEdit(added: removed, removed: added);

  InkEdit mergedWith(InkEdit next) => InkEdit(
        added: [...added, ...next.added],
        removed: [...removed, ...next.removed],
      );
}

/// Bounded linear undo/redo stack.
class UndoHistory {
  UndoHistory({this.limit = 200});

  final int limit;
  final List<InkEdit> _undo = [];
  final List<InkEdit> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Records a new edit and clears the redo stack. With [merge], the edit
  /// is folded into the previous one (e.g. one continuous eraser drag).
  void record(InkEdit edit, {bool merge = false}) {
    _redo.clear();
    if (merge && _undo.isNotEmpty) {
      _undo.add(_undo.removeLast().mergedWith(edit));
      return;
    }
    _undo.add(edit);
    if (_undo.length > limit) _undo.removeAt(0);
  }

  /// Pops the edit to undo; the caller applies its inverse.
  InkEdit? takeUndo() {
    if (_undo.isEmpty) return null;
    final edit = _undo.removeLast();
    _redo.add(edit);
    return edit;
  }

  /// Pops the edit to redo; the caller applies it.
  InkEdit? takeRedo() {
    if (_redo.isEmpty) return null;
    final edit = _redo.removeLast();
    _undo.add(edit);
    return edit;
  }
}
