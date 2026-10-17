import '../domain/stroke.dart';
import '../domain/surface_element.dart';

/// One undoable change to a surface: strokes added and/or removed, and
/// elements added, removed or replaced.
///
/// An element edit is a removal of its old value plus an addition of the
/// new value under the same id; applying the edit keeps the added value.
class InkEdit {
  InkEdit({
    List<Stroke>? added,
    List<Stroke>? removed,
    List<SurfaceElement>? addedElements,
    List<SurfaceElement>? removedElements,
  }) : added = added ?? const [],
       removed = removed ?? const [],
       addedElements = addedElements ?? const [],
       removedElements = removedElements ?? const [];

  final List<Stroke> added;
  final List<Stroke> removed;
  final List<SurfaceElement> addedElements;
  final List<SurfaceElement> removedElements;

  bool get isEmpty =>
      added.isEmpty && removed.isEmpty && addedElements.isEmpty && removedElements.isEmpty;

  InkEdit get inverse => InkEdit(
    added: removed,
    removed: added,
    addedElements: removedElements,
    removedElements: addedElements,
  );

  /// This edit followed by [next], as one. A value added here and removed
  /// again by [next] (e.g. a fragment the pixel eraser cut and then erased,
  /// or an intermediate version of an element) cancels out, so undo never
  /// resurrects it.
  InkEdit mergedWith(InkEdit next) {
    final strokes = _merge(added, removed, next.added, next.removed, (s) => s.id);
    final elements = _merge(
      addedElements,
      removedElements,
      next.addedElements,
      next.removedElements,
      (e) => e.id,
    );
    return InkEdit(
      added: strokes.added,
      removed: strokes.removed,
      addedElements: elements.added,
      removedElements: elements.removed,
    );
  }

  static ({List<T> added, List<T> removed}) _merge<T>(
    List<T> added,
    List<T> removed,
    List<T> nextAdded,
    List<T> nextRemoved,
    String Function(T) idOf,
  ) {
    final addedIds = {for (final v in added) idOf(v)};
    final cancelled = {
      for (final v in nextRemoved)
        if (addedIds.contains(idOf(v))) idOf(v),
    };
    return (
      added: [
        for (final v in added)
          if (!cancelled.contains(idOf(v))) v,
        ...nextAdded,
      ],
      removed: [
        ...removed,
        for (final v in nextRemoved)
          if (!cancelled.contains(idOf(v))) v,
      ],
    );
  }
}

/// Bounded linear undo/redo stack.
class UndoHistory {
  UndoHistory({this.limit = 200});

  final int limit;
  final List<InkEdit> _undo = [];
  final List<InkEdit> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// How many separate (unmerged) edits were ever [record]ed; tells a
  /// caller whether the last commit added an undo step or joined one.
  int get recorded => _recorded;
  int _recorded = 0;

  /// Records a new edit and clears the redo stack. With [merge], the edit
  /// is folded into the previous one (e.g. one continuous eraser drag).
  void record(InkEdit edit, {bool merge = false}) {
    _redo.clear();
    if (merge && _undo.isNotEmpty) {
      _undo.add(_undo.removeLast().mergedWith(edit));
      return;
    }
    _undo.add(edit);
    _recorded++;
    if (_undo.length > limit) _undo.removeAt(0);
  }

  /// Forgets every undo and redo step (the content they changed was
  /// rewritten beneath them, e.g. by a version restore).
  void clear() {
    _undo.clear();
    _redo.clear();
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
