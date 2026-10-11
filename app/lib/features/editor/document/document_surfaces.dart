import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../data/element_repository.dart';
import '../../../data/stroke_repository.dart';
import '../../../ink/images/element_images.dart';
import '../../../ink/render/chunk_picture_cache.dart';
import '../../../ink/render/tiles/ink_tile_cache.dart';
import '../../../ink/surface_model.dart';
import 'undo_target.dart';

/// One page's in-memory surface and its render cache.
class PageSurface {
  PageSurface(this.model) : cache = ChunkPictureCache(model) {
    tiles = InkTileCache(cache);
  }

  final SurfaceModel model;
  final ChunkPictureCache cache;

  /// Rendered tiles of the page's ink.
  late final InkTileCache tiles;

  bool get hasHistory => model.history.canUndo || model.history.canRedo;

  void dispose() {
    tiles.dispose();
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
  DocumentSurfaces(this.repository, {this.elements, this.images, this.keepIdle = 6});

  final StrokeRepository repository;

  /// Element (text box) storage; without it pages hold ink only.
  final ElementRepository? elements;

  /// Decoded bitmaps for image elements.
  final ElementImages? images;

  /// Off-screen surfaces without history kept around for quick returns.
  final int keepIdle;

  final Map<String, PageSurface> _surfaces = {};

  /// Notifies when a page's ink tiles were rendered (repaint only).
  Listenable get rendered => _rendered;
  final _rendered = ChangeNotifier();

  /// Least recently visible first.
  final List<String> _recency = [];

  /// The page of every undo step across the notebook (most recent last),
  /// and of every undone step that can be redone.
  final List<String> _undoPages = [];
  final List<String> _redoPages = [];

  /// [UndoHistory.recorded] of each page when last seen, to tell new undo
  /// steps from edits merged into the previous one.
  final Map<String, int> _recorded = {};

  /// The surface of page [pageId], created on demand.
  PageSurface surfaceOf(String pageId) {
    final existing = _surfaces[pageId];
    if (existing != null) return existing;
    final model =
        SurfaceModel(
            surfaceId: pageId,
            repository: repository,
            elementRepository: elements,
            images: images,
            writeBehind: true,
          )
          ..addListener(notifyListeners)
          ..onCommit = () => noteEdited(pageId);
    return _surfaces[pageId] = PageSurface(model)..tiles.addListener(_rendered.notifyListeners);
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
      _undoPages.removeWhere((e) => e == id);
      _redoPages.removeWhere((e) => e == id);
      _recorded.remove(id);
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
    s.tiles.removeListener(_rendered.notifyListeners);
    s.dispose();
  }

  // ---------------------------------------------------------------------------
  // Notebook-wide undo

  /// Records that [pageId] just committed an edit (a new undo step, or
  /// one merged into its previous step).
  void noteEdited(String pageId) {
    final model = _surfaces[pageId]?.model;
    if (model == null || !model.history.canUndo) return;
    final recorded = model.history.recorded;
    if (_recorded[pageId] != recorded) {
      _recorded[pageId] = recorded;
      _undoPages.add(pageId);
    }
    _redoPages.clear();
    notifyListeners();
  }

  @override
  bool get canUndo => _undoPages.any((id) => _surfaces[id]?.model.history.canUndo ?? false);
  @override
  bool get canRedo => _redoPages.any((id) => _surfaces[id]?.model.history.canRedo ?? false);

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
      final model = _surfaces[id]?.model;
      if (model == null) continue;
      if (undo ? !model.history.canUndo : !model.history.canRedo) continue;
      undo ? model.undo() : model.redo();
      to.add(id);
      return;
    }
  }

  @override
  void dispose() {
    for (final s in _surfaces.values) {
      s.model.removeListener(notifyListeners);
      s.dispose();
    }
    _surfaces.clear();
    _rendered.dispose();
    super.dispose();
  }
}
