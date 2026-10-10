import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../data/element_repository.dart';
import '../../../data/stroke_repository.dart';
import '../../../ink/render/chunk_picture_cache.dart';
import '../../../ink/surface_model.dart';
import 'undo_target.dart';

/// One page's in-memory surface and its render cache.
class PageSurface {
  PageSurface(this.model) : cache = ChunkPictureCache(model);

  final SurfaceModel model;
  final ChunkPictureCache cache;

  bool get hasHistory => model.history.canUndo || model.history.canRedo;

  void dispose() {
    cache.dispose();
    model.dispose();
  }
}

/// The surfaces of a paged notebook's pages, loaded only while visible.
///
/// A page's surface is created when it scrolls into view and released
/// again once it is off-screen — unless it has undo history, which must
/// survive scrolling. Notifies whenever any held surface changes.
///
/// Undo spans pages: the most recently edited page is undone first, like
/// one history for the whole notebook. Every committed edit (ink, text,
/// selection changes) counts, whether or not it came from a pointer.
class DocumentSurfaces extends ChangeNotifier implements UndoTarget {
  DocumentSurfaces(this.repository, {this.elements, this.keepIdle = 6});

  final StrokeRepository repository;

  /// Element (text box) storage; without it pages hold ink only.
  final ElementRepository? elements;

  /// Off-screen surfaces without history kept around for quick returns.
  final int keepIdle;

  final Map<String, PageSurface> _surfaces = {};

  /// Least recently visible first.
  final List<String> _recency = [];

  /// Pages in the order they were edited (most recent last).
  final List<String> _edited = [];
  final List<String> _undone = [];

  /// The surface of page [pageId], created on demand.
  PageSurface surfaceOf(String pageId) {
    final existing = _surfaces[pageId];
    if (existing != null) return existing;
    final model =
        SurfaceModel(surfaceId: pageId, repository: repository, elementRepository: elements)
          ..addListener(notifyListeners)
          ..onCommit = () => noteEdited(pageId);
    return _surfaces[pageId] = PageSurface(model);
  }

  /// The page receiving input; its surface is never released while idle
  /// (the input controller and editing tools hold on to it).
  String? active;

  /// Already-created surface of [pageId], if any.
  PageSurface? peek(String pageId) => _surfaces[pageId];

  Iterable<PageSurface> get all => _surfaces.values;

  /// Loads the visible parts of the given pages (page-local rectangles) and
  /// releases surfaces that are no longer needed.
  void showPages(Map<String, Rect> visible) {
    for (final entry in visible.entries) {
      _recency
        ..remove(entry.key)
        ..add(entry.key);
      surfaceOf(entry.key).model.ensureLoaded(entry.value);
    }
    final idle = [
      for (final id in _recency)
        if (!visible.containsKey(id) && id != active && !(_surfaces[id]?.hasHistory ?? false)) id,
    ];
    for (final id in idle.take(math.max(0, idle.length - keepIdle))) {
      _release(id);
    }
  }

  /// Forgets surfaces of pages that no longer exist.
  void retain(Set<String> pageIds) {
    for (final id in _surfaces.keys.where((id) => !pageIds.contains(id)).toList()) {
      _release(id);
      _edited.removeWhere((e) => e == id);
      _undone.removeWhere((e) => e == id);
    }
  }

  /// Reloads a page whose strokes changed remotely.
  void reload(String pageId) => _surfaces[pageId]?.model.reload();

  void _release(String id) {
    _recency.remove(id);
    final s = _surfaces.remove(id);
    if (s == null) return;
    s.model
      ..removeListener(notifyListeners)
      ..onCommit = null;
    s.dispose();
  }

  // ---------------------------------------------------------------------------
  // Notebook-wide undo

  /// Records that the user just finished a gesture on [pageId] that may
  /// have edited it.
  void noteEdited(String pageId) {
    final model = _surfaces[pageId]?.model;
    if (model == null || !model.history.canUndo) return;
    _edited
      ..remove(pageId)
      ..add(pageId);
    _undone.clear();
    notifyListeners();
  }

  @override
  bool get canUndo => _edited.any((id) => _surfaces[id]?.model.history.canUndo ?? false);
  @override
  bool get canRedo => _undone.any((id) => _surfaces[id]?.model.history.canRedo ?? false);

  @override
  void undo() {
    for (final id in _edited.reversed.toList()) {
      final model = _surfaces[id]?.model;
      if (model == null || !model.history.canUndo) continue;
      model.undo();
      _undone
        ..remove(id)
        ..add(id);
      if (!model.history.canUndo) _edited.remove(id);
      return;
    }
  }

  @override
  void redo() {
    for (final id in _undone.reversed.toList()) {
      final model = _surfaces[id]?.model;
      if (model == null || !model.history.canRedo) continue;
      model.redo();
      _edited
        ..remove(id)
        ..add(id);
      if (!model.history.canRedo) _undone.remove(id);
      return;
    }
  }

  /// Whether any page was edited in this session.
  bool get anyEdits => _surfaces.values.any((s) => s.hasHistory);

  @override
  void dispose() {
    for (final s in _surfaces.values) {
      s.model.removeListener(notifyListeners);
      s.dispose();
    }
    _surfaces.clear();
    super.dispose();
  }
}
