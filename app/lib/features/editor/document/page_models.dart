import 'package:flutter/foundation.dart';

import '../../../ink/surface_model.dart';
import 'undo_target.dart';

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
/// in whichever view it was made.
class PageModels extends ChangeNotifier implements UndoTarget {
  final Map<String, SurfaceModel> _models = {};
  final Map<String, int> _users = {};

  /// The page of every undo step across the notebook (most recent last),
  /// and of every undone step that can be redone.
  final List<String> _undoPages = [];
  final List<String> _redoPages = [];

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
    _undoPages.removeWhere((id) => !pageIds.contains(id));
    _redoPages.removeWhere((id) => !pageIds.contains(id));
    _recorded.removeWhere((id, _) => !pageIds.contains(id));
    _collect();
  }

  /// Reloads a page whose content changed remotely.
  void reload(String pageId) => _models[pageId]?.reload();

  bool _reachable(String id) => _undoPages.contains(id) || _redoPages.contains(id);

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
      _undoPages.add(pageId);
    }
    final redone = _redoPages.isNotEmpty;
    _redoPages.clear();
    if (redone) _collect();
    notifyListeners();
  }

  @override
  bool get canUndo => _undoPages.any((id) => _models[id]?.history.canUndo ?? false);
  @override
  bool get canRedo => _redoPages.any((id) => _models[id]?.history.canRedo ?? false);

  /// Undoes the most recent step on any page.
  @override
  void undo() => _step(_undoPages, _redoPages, undo: true);

  /// Redoes the most recently undone step.
  @override
  void redo() => _step(_redoPages, _undoPages, undo: false);

  /// Pops page ids off [from] until one can step (a page's own history may
  /// be shorter, e.g. after its limit), steps it and pushes it onto [to].
  void _step(List<String> from, List<String> to, {required bool undo}) {
    while (from.isNotEmpty) {
      final id = from.removeLast();
      final model = _models[id];
      if (model == null) continue;
      if (undo ? !model.history.canUndo : !model.history.canRedo) continue;
      undo ? model.undo() : model.redo();
      to.add(id);
      notifyListeners();
      return;
    }
  }

  @override
  void dispose() {
    for (final id in [..._models.keys]) {
      _dispose(id);
    }
    super.dispose();
  }
}
