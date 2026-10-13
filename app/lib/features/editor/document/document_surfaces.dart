import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../data/element_repository.dart';
import '../../../data/stroke_repository.dart';
import '../../../ink/images/element_images.dart';
import '../../../ink/render/chunk_picture_cache.dart';
import '../../../ink/render/chunk_raster_cache.dart';
import '../../../ink/render/outline_preparer.dart';
import '../../../ink/render/tiles/ink_tile_cache.dart';
import '../../../ink/surface_model.dart';
import 'page_models.dart';
import 'undo_target.dart';

/// One page's in-memory surface (shared by the notebook's views, see
/// [PageModels]) and this view's render cache of it.
class PageSurface {
  PageSurface(this.model) : cache = ChunkPictureCache(model) {
    tiles = InkTileCache(cache);
    rasters = ChunkRasterCache(cache, maxBytes: maxRasterBytes);
  }

  final SurfaceModel model;
  final ChunkPictureCache cache;

  /// Rendered tiles of the page's ink.
  late final InkTileCache tiles;

  /// Level-of-detail rasters of the page's chunks, drawn instead of tiles
  /// when zoomed out far (many pages on screen).
  late final ChunkRasterCache rasters;

  /// Memory a page's rasters may take (an A4 page is 2 × 3 chunks: all
  /// four levels of them take 2 MB).
  static const int maxRasterBytes = 4 << 20;

  /// Whether the surface must stay while off screen: it holds items of a
  /// selection made on another page. (A page with undo history may go:
  /// [PageModels] keeps its model while undo reaches it, without the
  /// render caches.)
  bool get pinned => model.hasHidden;

  /// Disposes the cache; the model is released to [PageModels].
  void dispose() {
    tiles.dispose();
    rasters.dispose();
    cache.dispose();
  }
}

/// The surfaces of a paged notebook's pages in one view, loaded only
/// while visible.
///
/// A page's surface is created when it scrolls into view and released
/// again once it is off-screen (its model stays while notebook-wide undo
/// reaches it, see [PageModels]). Notifies whenever any held surface
/// changes.
///
/// The models come from [models], which every view of the notebook shares
/// (and with it the notebook-wide undo this forwards to); each view keeps
/// its own render caches.
class DocumentSurfaces extends ChangeNotifier implements UndoTarget {
  DocumentSurfaces(
    this.repository, {
    this.elements,
    this.images,
    this.outlines,
    this.keepIdle = 6,
    PageModels? models,
  }) : models = models ?? PageModels(),
       _ownsModels = models == null {
    this.models.addListener(notifyListeners);
  }

  /// The notebook's page models and undo, shared by its views.
  final PageModels models;
  final bool _ownsModels;

  final StrokeRepository repository;

  /// Element (text box) storage; without it pages hold ink only.
  final ElementRepository? elements;

  /// Decoded bitmaps for image elements.
  final ElementImages? images;

  /// Builds loaded strokes' outlines off the UI thread (optional).
  final OutlinePreparer? outlines;

  /// Off-screen surfaces kept around for quick returns.
  final int keepIdle;

  final Map<String, PageSurface> _surfaces = {};

  /// Notifies when a page's ink tiles or rasters were rendered (repaint
  /// only).
  Listenable get rendered => _rendered;
  final _rendered = ChangeNotifier();

  /// Notifies when lifted content on a held page changed; whose it was is
  /// [lastLiftedOwner].
  Listenable get lifted => _lifted;
  final _lifted = ChangeNotifier();
  Object? lastLiftedOwner;
  final Map<String, VoidCallback> _liftedListeners = {};

  /// Least recently visible first.
  final List<String> _recency = [];

  /// The surface of page [pageId], created on demand.
  PageSurface surfaceOf(String pageId) {
    final existing = _surfaces[pageId];
    if (existing != null) return existing;
    final model = models.acquire(
      pageId,
      () => SurfaceModel(
        surfaceId: pageId,
        repository: repository,
        elementRepository: elements,
        images: images,
        writeBehind: true,
        outlines: outlines,
      ),
    )..addListener(notifyListeners);
    // Content an owner lifted out (a selection, a text editor) repaints
    // the ink painter, unless the owner is this view's own (see self).
    void onLifted() {
      lastLiftedOwner = model.lastLiftedOwner;
      _lifted.notifyListeners();
    }

    _liftedListeners[pageId] = onLifted;
    model.liftedChanges.addListener(onLifted);
    final surface = _surfaces[pageId] = PageSurface(model);
    surface.tiles.addListener(_rendered.notifyListeners);
    surface.rasters.addListener(_rendered.notifyListeners);
    return surface;
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
        if (!visible.containsKey(id) && id != active && !(_surfaces[id]?.pinned ?? false)) id,
    ];
    for (final id in idle.take(math.max(0, idle.length - keepIdle))) {
      _release(id);
    }
  }

  /// Forgets surfaces of pages that no longer exist.
  void retain(Set<String> pageIds) {
    for (final id in _surfaces.keys.where((id) => !pageIds.contains(id)).toList()) {
      _release(id);
    }
    models.retain(pageIds);
  }

  /// Reloads a page whose strokes changed remotely.
  void reload(String pageId) => models.reload(pageId);

  void _release(String id) {
    _recency.remove(id);
    final s = _surfaces.remove(id);
    if (s == null) return;
    s.model.removeListener(notifyListeners);
    final onLifted = _liftedListeners.remove(id);
    if (onLifted != null) s.model.liftedChanges.removeListener(onLifted);
    s.tiles.removeListener(_rendered.notifyListeners);
    s.rasters.removeListener(_rendered.notifyListeners);
    s.dispose();
    models.release(id);
  }

  // ---------------------------------------------------------------------------
  // Notebook-wide undo (see [PageModels])

  @override
  bool get canUndo => models.canUndo;
  @override
  bool get canRedo => models.canRedo;

  /// Undoes the most recent step on any page, in any view.
  @override
  void undo() => models.undo();

  /// Redoes the most recently undone step.
  @override
  void redo() => models.redo();

  @override
  void dispose() {
    for (final id in [..._surfaces.keys]) {
      _release(id);
    }
    _rendered.dispose();
    _lifted.dispose();
    models.removeListener(notifyListeners);
    if (_ownsModels) models.dispose();
    super.dispose();
  }
}
