import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/clock.dart';
import '../data/element_repository.dart';
import '../data/raster_store.dart';
import '../data/stroke_reader.dart';
import '../data/stroke_repository.dart';
import '../domain/chunk_digest.dart';
import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';
import '../domain/stroke_chunks.dart';
import '../domain/surface_element.dart';
import 'content_index.dart';
import 'geometry/stroke_splitter.dart';
import 'images/element_images.dart';
import 'pen/eraser_config.dart';
import 'render/outline_preparer.dart';
import 'stroke_hit_test.dart';
import 'surface_loader.dart';
import 'surface_views.dart';
import 'undo_history.dart';

/// The in-memory working set of one drawing surface (a page or a canvas):
/// its strokes and elements (text boxes).
///
/// Only chunks near the viewport are loaded from storage; far-away chunks
/// are evicted again, so memory and render cost depend on what is on screen
/// rather than on the total amount of content. Every edit is persisted
/// immediately, so the in-memory state is purely a cache plus undo history.
/// Draws content lifted out of a surface, in the surface's coordinates.
typedef LiftedPaint = void Function(Canvas canvas);

/// [source] (lifted content changing), heard only when the change came
/// from an owner outside [self] (whose [owner] is asked at the time): a
/// view's own selection dragging never repaints that view's ink.
class ForeignLiftedChanges implements Listenable {
  ForeignLiftedChanges(this.source, this.owner, this.self);

  final Listenable source;
  final Object? Function() owner;
  final Set<Object?> self;
  final Map<VoidCallback, VoidCallback> _wrapped = {};

  @override
  void addListener(VoidCallback listener) {
    void wrapped() {
      if (!self.contains(owner())) listener();
    }

    _wrapped[listener] = wrapped;
    source.addListener(wrapped);
  }

  @override
  void removeListener(VoidCallback listener) {
    final wrapped = _wrapped.remove(listener);
    if (wrapped != null) source.removeListener(wrapped);
  }
}

class SurfaceModel extends ChangeNotifier {
  SurfaceModel({
    required this.surfaceId,
    required this._repository,
    this._elementRepository,
    this.images,
    StrokeReader? reader,
    this.maxLoadedChunks = 1024,
    this.clock = const Clock(),
    this.writeBehind = false,
    this.outlines,
    this.rasterStore,
  }) {
    _loading = SurfaceLoader(
      reader: reader ?? _repository,
      surfaceId: surfaceId,
      skipFor: _loadedWithin,
      onLoad: _onLoad,
    );
  }

  /// Creates ids for strokes made by editing (pixel-eraser fragments).
  final Clock clock;

  final String surfaceId;
  final StrokeRepository _repository;

  /// Element storage; without it the surface holds ink only.
  final ElementRepository? _elementRepository;

  /// Decoded bitmaps for image elements (null: images show placeholders).
  final ElementImages? images;

  /// Where level-of-detail rasters of this surface's chunks persist, if
  /// anywhere (canvases, natively): a view zoomed far out draws them
  /// without loading the chunks (see [showStored]).
  final RasterStore? rasterStore;

  /// Soft cap on loaded chunks before far-away ones are evicted.
  final int maxLoadedChunks;

  /// Whether stroke edits are written to storage right after the frame
  /// that shows them instead of during the edit, so committing a stroke
  /// stays cheap. Reads, [reload] and [dispose] [flush] first.
  final bool writeBehind;

  final List<InkEdit> _unsaved = [];

  /// Builds loaded strokes' outlines before they are added (off the UI
  /// thread), so the first frame drawing a page does not build thousands
  /// of them; null: built when first drawn.
  final OutlinePreparer? outlines;

  /// Bumped by [reload]: loads prepared before are dropped.
  int _generation = 0;

  // Indexed with the same chunk functions as storage (path-based for ink).
  final _strokes = ContentIndex<Stroke>(idOf: (s) => s.id, chunksOf: StrokeChunks.of);
  final _elements = ContentIndex<SurfaceElement>(idOf: (e) => e.id, chunksOf: ElementChunks.of);

  /// Chunks whose stored content is fully in memory.
  final Set<ChunkKey> _loaded = {};

  /// Ids of strokes / elements not drawn by the committed layer (because a
  /// selection or text editor shows them instead).
  Set<String> _hidden = const {};

  final UndoHistory history = UndoHistory();

  /// Called after every committed (undoable) edit, e.g. so a notebook-wide
  /// undo knows which page changed last.
  VoidCallback? onCommit;

  final _changes = StreamController<SurfaceChange>.broadcast(sync: true);

  late final SurfaceLoader _loading;
  bool _disposed = false;

  /// What each view needs loaded.
  final SurfaceViews _views = SurfaceViews();

  /// Emits chunks whose rendering is stale; `null` means "everything".
  Stream<Set<ChunkKey>?> get invalidations => _changes.stream.map((c) => c.chunks);

  /// Like [invalidations], but tells appended strokes apart (see
  /// [SurfaceChange.appended]), so raster caches can add them to what they
  /// already rendered instead of rendering again.
  Stream<SurfaceChange> get changes => _changes.stream;

  int get loadedStrokeCount => _strokes.length;
  int get loadedElementCount => _elements.length;

  // ---------------------------------------------------------------------------
  // Queries

  /// Populated chunks within [range] (in memory).
  List<ChunkKey> chunksIn(ChunkRange range) {
    final strokes = _strokes.populatedIn(range);
    final elements = _elements.populatedIn(range);
    if (elements.isEmpty) return strokes;
    return {...strokes, ...elements}.toList();
  }

  /// Whether everything stored in [key] is in memory.
  bool isComplete(ChunkKey key) => _loaded.contains(key) && !_arriving.contains(key);

  /// The digest of [key]'s content when it is all in memory, not empty
  /// and drawn as stored: none hidden (selected, being edited). Null
  /// otherwise. (Images are content-addressed: an element's value names
  /// its blob by hash. Whether they are decoded yet is the renderer's
  /// business, see `ChunkPictureCache.isSettled`.)
  ChunkDigest? digestOf(ChunkKey key) {
    if (!isComplete(key)) return null;
    final strokes = _strokes.inChunk(key);
    final elements = _elements.inChunk(key);
    if (_hidden.isNotEmpty &&
        (strokes.any((s) => _hidden.contains(s.id)) ||
            elements.any((e) => _hidden.contains(e.id)))) {
      return null;
    }
    final digest = ChunkDigest.of(strokes, elements);
    return digest.strokes + digest.elements == 0 ? null : digest; // Emptied.
  }

  /// The digests of the populated chunks within [range] as stored (after
  /// writing pending edits).
  FutureOr<Map<ChunkKey, ChunkDigest>> storedDigests(ChunkRange range) {
    flush();
    return _loading.reader.chunkDigests(surfaceId, range);
  }

  /// Strokes overlapping [key], in paint order.
  List<Stroke> strokesInChunk(ChunkKey key) =>
      _strokes.inChunk(key).toList()..sort(Stroke.paintOrder);

  /// Elements overlapping [key], in stacking order.
  List<SurfaceElement> elementsInChunk(ChunkKey key) =>
      _elements.inChunk(key).toList()..sort(SurfaceElement.paintOrder);

  /// Candidate strokes whose chunks overlap [rect] (no precise test).
  Iterable<Stroke> strokesNear(Rect rect) => _strokes.query(rect);

  /// Elements whose bounds overlap [rect].
  Iterable<SurfaceElement> elementsNear(Rect rect) =>
      _elements.query(rect).where((e) => e.bounds.overlaps(rect));

  Stroke? strokeById(String id) => _strokes[id];
  SurfaceElement? elementById(String id) => _elements[id];

  /// The highest element stacking order loaded (for "new on top").
  double get topZ {
    var top = 0.0;
    for (final e in _elements.all) {
      if (e.z > top) top = e.z;
    }
    return top;
  }

  /// The lowest element stacking order loaded, at most 0.
  double get bottomZ {
    var bottom = 0.0;
    for (final e in _elements.query(Rect.largest)) {
      if (e.z < bottom) bottom = e.z;
    }
    return bottom;
  }

  /// The highest stacking order among loaded elements beneath the ink.
  double? get topBelowInkZ {
    double? top;
    for (final e in _elements.query(Rect.largest)) {
      if (e.belowInk && (top == null || e.z > top)) top = e.z;
    }
    return top;
  }

  // ---------------------------------------------------------------------------
  // Hiding (content shown elsewhere while selected or edited)

  bool isHidden(String id) => _hidden.contains(id);

  /// Whether some owner (a selection, a text editor) hides items here.
  bool get hasHidden => _hiddenBy.isNotEmpty;

  /// Replaces the stroke / element ids hidden by [owner] (e.g. a selection
  /// or a text editor). An item is hidden while any owner hides it, so two
  /// owners never un-hide each other's items.
  void setHidden(Set<String> ids, {Object? owner}) {
    if (_disposed) return;
    if (ids.isEmpty) {
      _hiddenBy.remove(owner);
    } else {
      _hiddenBy[owner] = ids;
    }
    final hidden = {for (final set in _hiddenBy.values) ...set};
    if (setEquals(hidden, _hidden)) return;
    final changed = <ChunkKey>{};
    final areas = <Rect>[];
    for (final id in {..._hidden, ...hidden}) {
      if (_hidden.contains(id) && hidden.contains(id)) continue;
      final stroke = _strokes[id];
      final element = _elements[id];
      if (stroke != null) {
        changed.addAll(StrokeChunks.of(stroke));
        areas.add(stroke.bounds);
      }
      if (element != null) {
        changed.addAll(ElementChunks.of(element));
        areas.add(element.bounds);
      }
    }
    _hidden = Set.unmodifiable(hidden);
    _changed(changed, areas: areas);
  }

  /// The ids each owner hides (see [setHidden]).
  final Map<Object?, Set<String>> _hiddenBy = {};

  /// What owners hiding items draw in their place, in this surface's
  /// coordinates: a selection its (moving) items, a text editor its box as
  /// typed. The owner's own view draws them itself; other views of this
  /// surface (split view) paint them from here ([paintLifted]) instead of
  /// showing a hole.
  final Map<Object, LiftedPaint> _lifted = {};

  /// Notifies when lifted content appears, changes or goes.
  Listenable get liftedChanges => _liftedChanges;
  final ChangeNotifier _liftedChanges = ChangeNotifier();

  /// Sets (or with null, removes) what [owner] draws in place of the items
  /// it hides.
  void setLifted(Object owner, LiftedPaint? paint) {
    // A selection or text session outliving the model (disposed later in
    // teardown) lets go of nothing that still draws.
    if (_disposed) return;
    if (paint == null) {
      if (_lifted.remove(owner) == null) return;
    } else {
      final had = _lifted.containsKey(owner);
      _lifted[owner] = paint;
      if (had) return; // Same owner, same paint: changes come by liftedChanged.
    }
    _notifyLifted(owner);
  }

  /// [owner]'s lifted content changed (it moved, was retyped).
  void liftedChanged(Object owner) {
    if (!_disposed && _lifted.containsKey(owner)) _notifyLifted(owner);
  }

  /// Whose lifted content changed last (see [ForeignLiftedChanges]).
  Object? get lastLiftedOwner => _lastLiftedOwner;
  Object? _lastLiftedOwner;

  void _notifyLifted(Object owner) {
    _lastLiftedOwner = owner;
    _liftedChanges.notifyListeners();
  }

  /// Whether owners other than [except] have lifted content here.
  bool hasLiftedExcept(Set<Object?> except) => _lifted.keys.any((o) => !except.contains(o));

  /// Paints the lifted content of owners other than [except] (in this
  /// surface's coordinates).
  void paintLifted(Canvas canvas, {Set<Object?> except = const {}}) {
    for (final MapEntry(key: owner, value: paint) in _lifted.entries) {
      if (!except.contains(owner)) paint(canvas);
    }
  }

  // ---------------------------------------------------------------------------
  // Loading

  /// Makes sure everything stored within (and around) [visibleWorld] is in
  /// memory, evicting far-away chunks if the working set grows too large.
  /// [view] tells views of one surface apart (see [showStored]).
  ///
  /// With a synchronous reader (the default) the chunks are loaded on
  /// return; with an asynchronous one they arrive later (see [isLoading]).
  void ensureLoaded(Rect visibleWorld, {Object? view}) {
    if (visibleWorld.isEmpty || !visibleWorld.isFinite) return;
    final range = _views.show(view, visibleWorld, stored: false);
    if (range != null) _request(range);
  }

  /// Like [ensureLoaded], for a [view] zoomed out so far that it draws
  /// stored rasters of the chunks ([rasterStore]): nothing is read for it,
  /// except chunks asked for with [requestChunks] (those without a raster)
  /// or, once something needs the content (a pen touching down),
  /// everything it shows ([loadVisible]).
  void showStored(Rect visibleWorld, {Object? view}) {
    if (visibleWorld.isEmpty || !visibleWorld.isFinite) return;
    _views.show(view, visibleWorld, stored: true);
  }

  /// Forgets what [view] needed (it is gone).
  void forgetView(Object? view) => _views.forget(view);

  /// Whether a view shows stored rasters (see [showStored]).
  bool get showsStored => _views.anyStored;

  /// Loads what [view] shows after [showStored] read only part of it:
  /// editing (erasing, selecting, writing) needs the content.
  void loadVisible({Object? view}) {
    final visible = _views.storedVisible(view);
    if (visible != null) ensureLoaded(visible, view: view);
  }

  /// Reads [keys] (chunks a [showStored] view has no raster of), if not in
  /// memory yet.
  void requestChunks(Iterable<ChunkKey> keys) {
    if (_disposed || !_views.anyStored) return;
    var added = false;
    for (final key in keys) {
      if (!_loaded.contains(key) && !_arriving.contains(key) && _views.wanted.add(key)) {
        added = true;
      }
    }
    if (added) _request(_views.wantedRange!);
  }

  /// Reads the chunks of [range] not in memory — and those still wanted,
  /// with what other views need: a newer request replaces one queued.
  void _request(ChunkRange range) {
    var r = range;
    for (final other in [?_views.wantedRange, ..._views.loadedRanges]) {
      r = ChunkRange(
        math.min(r.minX, other.minX),
        math.min(r.minY, other.minY),
        math.max(r.maxX, other.maxX),
        math.max(r.maxY, other.maxY),
      );
    }
    flush(); // Reads must see every edit.
    _loading.request(r);
  }

  /// Whether chunks are still being read (or their outlines built).
  bool get isLoading => _loading.isLoading || _preparing > 0;

  /// Completes when no background read is pending.
  Future<void> get loaded async {
    await _loading.idle;
    while (_preparing > 0 && !_disposed) {
      await Future<void>.delayed(const Duration(milliseconds: 4));
    }
  }

  int _preparing = 0;

  /// Ids removed while loads were being prepared: those loads must not
  /// bring them back.
  final Set<String> _removedWhilePreparing = {};

  /// Chunks read but not added yet (their outlines are being built): not
  /// read again meanwhile.
  final Set<ChunkKey> _arriving = {};

  Set<ChunkKey> _loadedWithin(ChunkRange range) => {
    for (final key in _loaded)
      if (range.contains(key)) key,
    for (final key in _arriving)
      if (range.contains(key)) key,
    // Views showing stored rasters read only the chunks asked for.
    if (_views.anyStored)
      for (final key in range.keys)
        if (_views.skips(key)) key,
  };

  void _onLoad(ChunkLoad load) {
    if (_disposed) return;
    final outlines = this.outlines;
    if (outlines == null || load.strokes.isEmpty) return _insertLoad(load);
    final generation = _generation;
    bool current() => !_disposed && generation == _generation;
    _preparing++;
    _arriving.addAll(load.chunks);
    // Strokes are added as their outlines arrive, a chunk's worth at a
    // time (by first point), those nearest the middle of the view first,
    // so a large load (a whole canvas seen from afar) fills in from where
    // the user looks instead of showing nothing until its last outline is
    // built — and each chunk is re-rendered about once, not per slice.
    // Synchronous when the outlines are built inline.
    final groups = _nearestFirst(load.strokes);
    final groupOf = Map<Stroke, int>.identity();
    for (var g = 0; g < groups.length; g++) {
      for (final s in groups[g]) {
        groupOf[s] = g;
      }
    }
    final waiting = [for (final g in groups) g.length];
    outlines
        .prepare(
          [for (final g in groups) ...g],
          onReady: (ready) {
            if (!current()) return;
            final complete = <Stroke>[];
            for (final s in ready) {
              final g = groupOf[s];
              if (g != null && --waiting[g] == 0) complete.addAll(groups[g]);
            }
            if (complete.isNotEmpty) _insertStrokes(complete);
          },
        )
        .then((_) {
          _preparing--;
          if (current()) {
            _arriving.removeAll(load.chunks);
            final removed = _removedWhilePreparing;
            _insertLoad(
              removed.isEmpty
                  ? load
                  : ChunkLoad(
                      chunks: load.chunks,
                      strokes: [
                        for (final s in load.strokes)
                          if (!removed.contains(s.id)) s,
                      ],
                      elements: [
                        for (final e in load.elements)
                          if (!removed.contains(e.id)) e,
                      ],
                    ),
            );
          }
          if (_preparing == 0) _removedWhilePreparing.clear();
        });
  }

  /// [strokes] grouped by the chunk of their first point, the groups
  /// ordered by their distance from the middle of the last visible area.
  List<List<Stroke>> _nearestFirst(List<Stroke> strokes) {
    final visible = _views.lastVisible;
    final byChunk = <ChunkKey, List<Stroke>>{};
    for (final s in strokes) {
      final p = s.points.isEmpty ? null : s.points.first;
      (byChunk[ChunkGrid.keyAt(p?.x ?? 0, p?.y ?? 0)] ??= []).add(s);
    }
    final keys = byChunk.keys.toList();
    if (visible != null && keys.length > 1) {
      final centre = visible.center;
      double distance(ChunkKey k) => (ChunkGrid.rectOf(k).center - centre).distanceSquared;
      keys.sort((a, b) => distance(a).compareTo(distance(b)));
    }
    return [for (final k in keys) byChunk[k]!];
  }

  /// Adds loaded [strokes] whose outlines are ready (the rest of their
  /// load, and its chunks, follow in [_insertLoad]).
  void _insertStrokes(List<Stroke> strokes) {
    developer.Timeline.startSync('len.insertLoaded');
    final changed = <ChunkKey>{};
    final removed = _removedWhilePreparing;
    for (final stroke in strokes) {
      if (_strokes.containsId(stroke.id) || removed.contains(stroke.id)) continue;
      _strokes.insert(stroke);
      changed.addAll(StrokeChunks.of(stroke));
    }
    developer.Timeline.startSync('len.loadedChanged');
    if (changed.isNotEmpty) _changed(changed, loaded: true);
    developer.Timeline.finishSync();
    developer.Timeline.finishSync();
  }

  void _insertLoad(ChunkLoad load) {
    if (load.chunks.isNotEmpty) {
      final changed = <ChunkKey>{};
      for (final stroke in load.strokes) {
        if (_strokes.containsId(stroke.id)) continue;
        _strokes.insert(stroke);
        changed.addAll(StrokeChunks.of(stroke));
      }
      // Without element storage the surface holds ink only.
      if (_elementRepository != null) {
        for (final element in load.elements) {
          if (_elements.containsId(element.id)) continue;
          _elements.insert(element);
          changed.addAll(ElementChunks.of(element));
        }
      }
      _loaded.addAll(load.chunks);
      if (changed.isNotEmpty) _changed(changed, loaded: true);
    }
    _views.wanted.removeAll(load.chunks);
    if (_loaded.length > maxLoadedChunks) _evictOutside();
  }

  /// Drops everything in memory and reloads from storage (e.g. after a sync
  /// brought in remote changes).
  void reload() {
    flush();
    _generation++;
    _strokes.clear();
    _elements.clear();
    _loaded.clear();
    _arriving.clear();
    _views.clear();
    _loading.reset();
    _changes.add(const SurfaceChange(null));
    final ranges = _views.loadedRanges;
    if (ranges.isNotEmpty) _request(ranges.first);
    notifyListeners();
  }

  /// Unloads every chunk away from the views. An item stays in memory while any
  /// loaded chunk still needs it. Only the affected chunks are invalidated,
  /// so cached pictures of what is on screen survive.
  void _evictOutside() {
    final evicted = <ChunkKey>{};
    final strokes = <Stroke>{};
    final elements = <SurfaceElement>{};
    _loaded.removeWhere((key) {
      if (_views.keeps(key)) return false;
      evicted.add(key);
      strokes.addAll(_strokes.inChunk(key));
      elements.addAll(_elements.inChunk(key));
      return true;
    });
    for (final s in strokes) {
      final keys = StrokeChunks.of(s);
      if (keys.any(_loaded.contains) || _hidden.contains(s.id)) continue;
      _removeStroke(s);
      evicted.addAll(keys);
    }
    for (final e in elements) {
      final keys = ElementChunks.of(e);
      if (keys.any(_loaded.contains) || _hidden.contains(e.id)) continue;
      _removeElement(e);
      evicted.addAll(keys);
    }
    // Nothing visible changed, so listeners need not be notified.
    if (evicted.isNotEmpty) _changes.add(SurfaceChange(evicted));
  }

  // ---------------------------------------------------------------------------
  // Editing

  /// Adds a newly drawn stroke (persisted immediately, undoable).
  void addStroke(Stroke stroke) => commit(InkEdit(added: [stroke]));

  /// Applies [edit] (persisted immediately) and records it for undo. With
  /// [merge], it joins the previous undo step (one continuous gesture).
  ///
  /// Ignored once disposed (its page is gone): nothing is written to it.
  void commit(InkEdit edit, {bool merge = false}) {
    if (edit.isEmpty || _disposed) return;
    _apply(edit);
    history.record(edit, merge: merge);
    onCommit?.call();
  }

  /// Erases along the eraser sweep from [a] to [b]: in [EraserMode.stroke]
  /// every touched stroke is removed; in [EraserMode.pixel] only the ink
  /// under the eraser is, and the surviving parts are added as new strokes.
  /// With [highlighterOnly], pen ink is left alone.
  ///
  /// Consecutive calls with [continueEdit] merge into one undo step.
  /// Returns whether anything was erased.
  bool eraseAlong(
    Offset a,
    Offset b,
    double radius, {
    required bool continueEdit,
    EraserMode mode = EraserMode.stroke,
    bool highlighterOnly = false,
  }) {
    final sweep = Rect.fromPoints(a, b).inflate(radius);
    final removed = <Stroke>[];
    final added = <Stroke>[];
    for (final stroke in _strokes.query(sweep)) {
      if (highlighterOnly && !stroke.tool.isHighlighter) continue;
      if (_hidden.contains(stroke.id)) continue;
      if (mode == EraserMode.stroke) {
        if (StrokeHitTest.sweepHits(stroke, a, b, radius)) removed.add(stroke);
        continue;
      }
      final fragments = StrokeSplitter.erase(stroke, a, b, radius, newId: clock.newId);
      if (fragments == null) continue;
      removed.add(stroke);
      added.addAll(fragments);
    }
    if (removed.isEmpty) return false;
    commit(
      InkEdit(added: added, removed: removed),
      merge: continueEdit,
    );
    return true;
  }

  void undo() {
    if (_disposed) return;
    final edit = history.takeUndo();
    if (edit != null) _apply(edit.inverse);
  }

  void redo() {
    if (_disposed) return;
    final edit = history.takeRedo();
    if (edit != null) _apply(edit);
  }

  void _apply(InkEdit edit) {
    final changed = <ChunkKey>{};

    if (edit.removed.isNotEmpty || edit.added.isNotEmpty) {
      if (writeBehind) {
        _unsaved.add(edit);
        if (_withUnsaved.add(this)) {
          // After the frame that shows the edit is handed to the raster
          // thread, so the write runs alongside its rasterisation.
          SchedulerBinding.instance
            ..addPostFrameCallback((_) => flush())
            ..ensureVisualUpdate();
        }
      } else {
        _write(edit);
      }
    }
    if (_preparing > 0) {
      _removedWhilePreparing
        ..addAll(edit.removed.map((s) => s.id))
        ..addAll(edit.removedElements.map((e) => e.id));
    }
    final areas = <Rect>[];
    for (final s in edit.removed) {
      final current = _strokes[s.id];
      if (current != null) _removeStroke(current);
      changed.addAll(StrokeChunks.of(s));
      areas.add(s.bounds);
    }
    final appended = _isAppend(edit);
    for (final s in edit.added) {
      _strokes.insert(s);
      changed.addAll(StrokeChunks.of(s));
      areas.add(s.bounds);
    }

    // An element replaced by a new value keeps its id: only delete the
    // ones that are not re-added.
    final keptIds = {for (final e in edit.addedElements) e.id};
    final deleted = [
      for (final e in edit.removedElements)
        if (!keptIds.contains(e.id)) e.id,
    ];
    if (deleted.isNotEmpty) _elementRepository?.delete(deleted);
    if (edit.addedElements.isNotEmpty) _elementRepository?.save(edit.addedElements);
    for (final e in edit.removedElements) {
      final current = _elements[e.id];
      if (current != null) {
        _removeElement(current);
        changed.addAll(ElementChunks.of(current));
        areas.add(current.bounds);
      }
      changed.addAll(ElementChunks.of(e));
      areas.add(e.bounds);
    }
    for (final e in edit.addedElements) {
      _elements.insert(e);
      changed.addAll(ElementChunks.of(e));
      areas.add(e.bounds);
    }
    _changed(changed, appended: appended ? edit.added : null, areas: areas);
  }

  /// Whether [edit] only adds pen strokes painted over everything already
  /// in their chunks (nothing above the ink there, nothing hidden), so
  /// drawing them over a rendering of the chunks before the edit gives the
  /// rendering after it. Checked before the strokes are inserted.
  bool _isAppend(InkEdit edit) {
    if (edit.added.isEmpty || edit.removed.isNotEmpty) return false;
    if (edit.addedElements.isNotEmpty || edit.removedElements.isNotEmpty) return false;
    for (final s in edit.added) {
      if (s.tool.isHighlighter || _strokes.containsId(s.id) || _hidden.contains(s.id)) {
        return false;
      }
      for (final key in StrokeChunks.of(s)) {
        for (final other in _strokes.inChunk(key)) {
          if (Stroke.paintOrder(other, s) > 0) return false;
        }
        if (_elements.inChunk(key).any((e) => !e.belowInk)) return false;
      }
    }
    return true;
  }

  /// Models with edits waiting for [writeBehind].
  static final Set<SurfaceModel> _withUnsaved = {};

  /// [flush]es every surface, before code that reads or rewrites stored
  /// strokes directly (page copies and deletions, exports).
  static void flushAll() {
    for (final model in List.of(_withUnsaved)) {
      model.flush();
    }
  }

  /// Writes stroke edits still waiting for [writeBehind] to storage.
  void flush() {
    _withUnsaved.remove(this);
    if (_unsaved.isEmpty) return;
    final edits = List.of(_unsaved);
    _unsaved.clear();
    edits.forEach(_write);
  }

  void _write(InkEdit edit) {
    developer.Timeline.startSync('len.persistStrokes');
    if (edit.removed.isNotEmpty) _repository.delete(edit.removed.map((s) => s.id));
    if (edit.added.isNotEmpty) _repository.save(edit.added);
    developer.Timeline.finishSync();
  }

  /// Marks [chunks] for re-rendering although no content changed (e.g. an
  /// image in them finished decoding).
  void refresh(Set<ChunkKey> chunks) {
    if (chunks.isNotEmpty) _changed(chunks);
  }

  // ---------------------------------------------------------------------------
  // Internals

  /// Removals go through here so a background read in flight cannot bring
  /// back a stale copy (see [SurfaceLoader.noteRemoved]).
  void _removeStroke(Stroke stroke) {
    _strokes.remove(stroke);
    _loading.noteRemoved(stroke.id);
  }

  void _removeElement(SurfaceElement element) {
    _elements.remove(element);
    _loading.noteRemoved(element.id);
  }

  void _changed(
    Set<ChunkKey> chunks, {
    List<Stroke>? appended,
    bool loaded = false,
    List<Rect>? areas,
  }) {
    _changes.add(SurfaceChange(chunks, appended: appended, loaded: loaded, areas: areas));
    notifyListeners();
  }

  @override
  void dispose() {
    flush();
    _disposed = true;
    _loading.dispose();
    _liftedChanges.dispose();
    _changes.close();
    super.dispose();
  }
}

/// A change of what a surface renders: the [chunks] whose rendering is
/// stale (null: everything).
class SurfaceChange {
  const SurfaceChange(this.chunks, {this.appended, this.loaded = false, this.areas});

  final Set<ChunkKey>? chunks;

  /// The world rectangles within [chunks] whose rendering changed (the
  /// bounds of the items edited), when known; null: all of [chunks].
  final List<Rect>? areas;

  /// Set when the change only appends these strokes on top of everything
  /// in [chunks] (pen ink, nothing above it there): a rendering of the
  /// chunks from before plus these strokes, in order, is up to date.
  final List<Stroke>? appended;

  /// Set when the change only brings in stored content (a load): a
  /// rendering from before may stand in until a new one is made, as the
  /// content was not on screen yet anyway (nothing the user did vanishes
  /// or lingers).
  final bool loaded;
}
