part of 'rich_text_controller.dart';

/// A state of the box being edited: its formatted text and the selection
/// (box-text offsets).
typedef _Snapshot = ({TextData data, TextSelection selection});

/// Undo and redo inside the box being edited, formatting included (the
/// text field's own undo only knows plain text). A run of typed characters
/// up to a space or line break, or of characters deleted one by one, is one
/// step; so is an IME composition (pinyin, romaji) with its commit.
class _TextHistory {
  static const _limit = 200;

  final _undo = <_Snapshot>[];
  final _redo = <_Snapshot>[];

  /// The state after the last change, with the selection since.
  _Snapshot? _last;

  /// The caret offset where the current typing (or deleting) run goes on,
  /// or -1.
  int _runAt = -1;
  bool _runDeletes = false;

  /// Whether the last change left an IME composition open.
  bool _composing = false;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Starts over at [state] (another box loaded).
  void reset(_Snapshot state) {
    _undo.clear();
    _redo.clear();
    _last = state;
    _runAt = -1;
    _composing = false;
  }

  /// The selection moved to [selection] without a change.
  void select(TextSelection selection) {
    final last = _last;
    if (last != null) _last = (data: last.data, selection: selection);
  }

  /// The text changed to [state]. A typing run continues when the edit
  /// starts at [runFrom] where the last one ended; it then goes on at
  /// [runTo] (-1 ends the run). Changes while [composing] (and the one
  /// that ends the composition) go on the same step.
  void changed(
    _Snapshot state, {
    int runFrom = -1,
    int runTo = -1,
    bool deletes = false,
    bool composing = false,
  }) {
    final last = _last;
    final continues = _composing || (runFrom >= 0 && runFrom == _runAt && deletes == _runDeletes);
    _composing = composing;
    if (!continues && last != null) {
      _undo.add(last);
      if (_undo.length > _limit) _undo.removeAt(0);
    }
    _redo.clear();
    _last = state;
    _runAt = runTo;
    _runDeletes = deletes;
  }

  /// The state to go back to from [now], or null.
  _Snapshot? undo(_Snapshot now) => _step(_undo, _redo, now);

  /// The state undone last (from [now]), or null.
  _Snapshot? redo(_Snapshot now) => _step(_redo, _undo, now);

  _Snapshot? _step(List<_Snapshot> from, List<_Snapshot> to, _Snapshot now) {
    if (from.isEmpty) return null;
    to.add(now);
    _runAt = -1;
    _composing = false;
    return _last = from.removeLast();
  }
}
