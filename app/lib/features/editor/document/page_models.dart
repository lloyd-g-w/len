import 'package:flutter/foundation.dart';

import '../../../ink/surface_model.dart';
import 'undo_target.dart';

/// A notebook-level change that is not ink on a page (a template, the page
/// order, bookmarks, pages added or deleted), undone and redone by the
/// callbacks it was made with. Each callback changes the stored data and
/// shows the result.
class PageEdit {
  PageEdit({required this.undo, required this.redo});

  final VoidCallback undo;
  final VoidCallback redo;
}

/// The page models (ink, elements, undo history) of one paged notebook,
/// shared by every view of it: two views of a notebook (split view) draw
/// into, see and undo the very same models, so they never disagree.
///
/// Each view's `DocumentSurfaces` [acquire]s the pages it shows and
/// [release]s them again; a model is disposed once no view holds it and
/// notebook-wide undo cannot reach it any more.
///
/// Undo spans pages: the most recently edited page is undone first, like
/// one history for the whole notebook. Every committed edit (ink, text,
/// selection changes) counts, whether or not it came from a pointer, and
/// in whichever view it was made. Page-level changes ([PageEdit]s: a
/// template, the page order, bookmarks, pages deleted) are steps of the
/// same history, so Ctrl+Z takes back whatever was done last. It reaches
/// back [maxSteps] steps on at most [maxPages] pages: every page it reaches
/// keeps its model (all its ink, loaded) in memory.
class PageModels extends ChangeNotifier implements UndoTarget {
  /// Most undo steps kept across the notebook (a page keeps as many).
  static const maxSteps = 200;

  /// Most pages the undo history reaches; older steps are dropped.
  static const maxPages = 24;

  final Map<String, SurfaceModel> _models = {};
  final Map<String, int> _users = {};

  /// The pages of every undo step across the notebook (most recent last),
  /// and of every undone step that can be redone. A step is usually one
  /// page's; a [group] (e.g. a selection moved across pages) lists each
  /// page's own step in the order they were made. Entries are page ids or
  /// [PageEdit]s.
  final List<List<Object>> _undoPages = [];
  final List<List<Object>> _redoPages = [];

  /// The steps made while a [group] runs.
  List<Object>? _grouping;

  /// [UndoHistory.recorded] of each page when last seen, to tell new undo
  /// steps from edits merged into the previous one.
  final Map<String, int> _recorded = {};

  /// The model of page [pageId] (made by [create] if no view holds it),
  /// held until [release]d.
  SurfaceModel acquire(String pageId, SurfaceModel Function() create) {
    _users[pageId] = (_users[pageId] ?? 0) + 1;
    return _models[pageId] ??= create()..onCommit = () => noteEdited(pageId);
  }

  /// The model of page [pageId] if one exists.
  SurfaceModel? peek(String pageId) => _models[pageId];

  /// Gives up one hold on page [pageId]'s model.
  void release(String pageId) {
    final users = (_users[pageId] ?? 1) - 1;
    if (users > 0) {
      _users[pageId] = users;
      return;
    }
    _users.remove(pageId);
    if (!_reachable(pageId)) _dispose(pageId);
  }

  /// Forgets the undo steps of pages that no longer exist (and their
  /// models, once no view holds them).
  void retain(Set<String> pageIds) {
    for (final steps in [_undoPages, _redoPages]) {
      for (final step in steps) {
        step.removeWhere((id) => id is String && !pageIds.contains(id));
      }
      steps.removeWhere((step) => step.isEmpty);
    }
    _recorded.removeWhere((id, _) => !pageIds.contains(id));
    _collect();
  }

  /// Reloads a page whose content changed remotely.
  void reload(String pageId) => _models[pageId]?.reload();

  bool _reachable(String id) =>
      _undoPages.any((step) => step.contains(id)) || _redoPages.any((step) => step.contains(id));

  /// Disposes models no view holds and undo no longer reaches.
  void _collect() {
    for (final id in [..._models.keys]) {
      if (!_users.containsKey(id) && !_reachable(id)) _dispose(id);
    }
  }

  void _dispose(String id) {
    final model = _models.remove(id);
    if (model == null) return;
    model.onCommit = null;
    model.dispose();
  }

  /// Records that [pageId] just committed an edit (a new undo step, or
  /// one merged into its previous step).
  void noteEdited(String pageId) {
    final model = _models[pageId];
    if (model == null || !model.history.canUndo) return;
    final recorded = model.history.recorded;
    if (_recorded[pageId] != recorded) {
      _recorded[pageId] = recorded;
      _add(pageId);
    }
    _clearRedo();
    notifyListeners();
  }

  /// Records [edit], already made, as an undo step (part of the running
  /// [group], if any).
  void record(PageEdit edit) {
    _add(edit);
    _clearRedo();
    notifyListeners();
  }

  /// Takes back [edit] wherever it is in the history (a snack bar's Undo,
  /// pressed after later edits): the latest step is undone as usual; an
  /// older one is undone and dropped. False if [edit] is not undoable.
  bool undoEdit(PageEdit edit) {
    if (_undoPages.isNotEmpty && _undoPages.last.contains(edit)) {
      undo();
      return true;
    }
    final step = _undoPages.where((s) => s.contains(edit)).firstOrNull;
    if (step == null) return false;
    step.remove(edit);
    if (step.isEmpty) _undoPages.remove(step);
    edit.undo();
    notifyListeners();
    return true;
  }

  void _add(Object entry) {
    final group = _grouping;
    if (group != null) return group.add(entry);
    _undoPages.add([entry]);
    _trim();
  }

  /// Drops the oldest undo steps beyond [maxSteps] or [maxPages], and the
  /// models only they kept.
  void _trim() {
    var dropped = false;
    while (_undoPages.length > maxSteps ||
        {for (final step in _undoPages) ...step.whereType<String>()}.length > maxPages) {
      _undoPages.removeAt(0);
      dropped = true;
    }
    if (dropped) _collect();
  }

  void _clearRedo() {
    final redone = _redoPages.isNotEmpty;
    _redoPages.clear();
    if (redone) _collect();
  }

  /// Runs [edits] — commits on several pages — as one notebook-wide undo
  /// step: undo takes back each page's part (latest first), redo replays
  /// them in order.
  void group(void Function() edits) {
    if (_grouping != null) return edits();
    final group = _grouping = [];
    try {
      edits();
    } finally {
      _grouping = null;
      if (group.isNotEmpty) {
        _undoPages.add(group);
        _trim();
      }
      notifyListeners();
    }
  }

  @override
  bool get canUndo => _undoPages.any((step) => step.any(_canUndo));
  @override
  bool get canRedo => _redoPages.any((step) => step.any(_canRedo));

  bool _canUndo(Object id) => id is PageEdit || (_models[id]?.history.canUndo ?? false);
  bool _canRedo(Object id) => id is PageEdit || (_models[id]?.history.canRedo ?? false);

  /// Undoes the most recent step on any page.
  @override
  void undo() => _step(_undoPages, _redoPages, undo: true);

  /// Redoes the most recently undone step.
  @override
  void redo() => _step(_redoPages, _undoPages, undo: false);

  /// Pops steps off [from] until one can step (a page's own history may
  /// be shorter, e.g. after its limit), steps each of its pages (backwards
  /// to undo) and pushes it onto [to].
  void _step(List<List<Object>> from, List<List<Object>> to, {required bool undo}) {
    while (from.isNotEmpty) {
      final step = from.removeLast();
      final pages = undo ? step.reversed : step;
      var stepped = false;
      for (final id in pages) {
        if (id is PageEdit) {
          undo ? id.undo() : id.redo();
          stepped = true;
          continue;
        }
        final model = _models[id];
        if (model == null || !(undo ? _canUndo(id) : _canRedo(id))) continue;
        undo ? model.undo() : model.redo();
        stepped = true;
      }
      if (!stepped) continue;
      to.add(step);
      notifyListeners();
      return;
    }
  }

  bool _disposed = false;

  /// Page edits outlive the editors (a snack bar's Undo pressed back in
  /// the library still restores pages): nothing to tell once disposed.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final id in [..._models.keys]) {
      _dispose(id);
    }
    super.dispose();
  }
}
