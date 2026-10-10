import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import '../data/element_repository.dart';
import '../data/stroke_repository.dart';
import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';
import '../domain/surface_element.dart';
import 'content_index.dart';
import 'geometry/stroke_splitter.dart';
import 'pen/eraser_config.dart';
import 'stroke_hit_test.dart';
import 'undo_history.dart';

/// The in-memory working set of one drawing surface (a page or a canvas):
/// its strokes and elements (text boxes).
///
/// Only chunks near the viewport are loaded from storage; far-away chunks
/// are evicted again, so memory and render cost depend on what is on screen
/// rather than on the total amount of content. Every edit is persisted
/// immediately, so the in-memory state is purely a cache plus undo history.
class SurfaceModel extends ChangeNotifier {
  SurfaceModel({
    required this.surfaceId,
    required this._repository,
    this._elementRepository,
    this.maxLoadedChunks = 1024,
    this.clock = const Clock(),
  });

  /// Creates ids for strokes made by editing (pixel-eraser fragments).
  final Clock clock;

  final String surfaceId;
  final StrokeRepository _repository;

  /// Element storage; without it the surface holds ink only.
  final ElementRepository? _elementRepository;

  /// Soft cap on loaded chunks before far-away ones are evicted.
  final int maxLoadedChunks;

  final _strokes = ContentIndex<Stroke>(idOf: (s) => s.id, boundsOf: (s) => s.bounds);
  final _elements = ContentIndex<SurfaceElement>(idOf: (e) => e.id, boundsOf: (e) => e.bounds);

  /// Chunks whose stored content is fully in memory.
  final Set<ChunkKey> _loaded = {};

  /// Ids of strokes / elements not drawn by the committed layer (because a
  /// selection or text editor shows them instead).
  Set<String> _hidden = const {};

  final UndoHistory history = UndoHistory();

  final _invalidations = StreamController<Set<ChunkKey>?>.broadcast(sync: true);

  ChunkRange? _lastRange;
  Rect? _lastVisible;

  /// Emits chunks whose rendering is stale; `null` means "everything".
  Stream<Set<ChunkKey>?> get invalidations => _invalidations.stream;

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
    for (final e in _elements.query(Rect.largest)) {
      if (e.z > top) top = e.z;
    }
    return top;
  }

  // ---------------------------------------------------------------------------
  // Hiding (content shown elsewhere while selected or edited)

  bool isHidden(String id) => _hidden.contains(id);

  /// Replaces the set of hidden stroke / element ids.
  void setHidden(Set<String> ids) {
    if (setEquals(ids, _hidden)) return;
    final changed = <ChunkKey>{};
    for (final id in {..._hidden, ...ids}) {
      final bounds = _strokes[id]?.bounds ?? _elements[id]?.bounds;
      if (bounds != null) changed.addAll(ChunkGrid.rangeFor(bounds).keys);
    }
    _hidden = Set.unmodifiable(ids);
    _changed(changed);
  }

  // ---------------------------------------------------------------------------
  // Loading

  /// Makes sure everything stored within (and around) [visibleWorld] is in
  /// memory, evicting far-away chunks if the working set grows too large.
  void ensureLoaded(Rect visibleWorld) {
    if (visibleWorld.isEmpty || !visibleWorld.isFinite) return;
    _lastVisible = visibleWorld;
    final range = ChunkGrid.rangeFor(visibleWorld.inflate(ChunkGrid.size));
    if (range == _lastRange) return;
    _lastRange = range;

    final elementRepo = _elementRepository;
    final missing = {
      ..._repository.populatedChunks(surfaceId, range),
      ...?elementRepo?.populatedChunks(surfaceId, range),
    }.where((key) => !_loaded.contains(key)).toList();
    if (missing.isNotEmpty) {
      final changed = <ChunkKey>{};
      for (final stroke in _repository.loadChunks(surfaceId, missing)) {
        if (_strokes.containsId(stroke.id)) continue;
        _strokes.insert(stroke);
        changed.addAll(ChunkGrid.rangeFor(stroke.bounds).keys);
      }
      for (final element
          in elementRepo?.loadChunks(surfaceId, missing) ?? const <SurfaceElement>[]) {
        if (_elements.containsId(element.id)) continue;
        _elements.insert(element);
        changed.addAll(ChunkGrid.rangeFor(element.bounds).keys);
      }
      _loaded.addAll(missing);
      if (changed.isNotEmpty) _changed(changed);
    }
    if (_loaded.length > maxLoadedChunks) _evictOutside(range);
  }

  /// Drops everything in memory and reloads from storage (e.g. after a sync
  /// brought in remote changes).
  void reload() {
    _strokes.clear();
    _elements.clear();
    _loaded.clear();
    _lastRange = null;
    _invalidations.add(null);
    final visible = _lastVisible;
    if (visible != null) ensureLoaded(visible);
    notifyListeners();
  }

  /// Unloads every chunk outside [keep]. An item stays in memory while any
  /// loaded chunk still needs it. Only the affected chunks are invalidated,
  /// so cached pictures of what is on screen survive.
  void _evictOutside(ChunkRange keep) {
    final evicted = <ChunkKey>{};
    final strokes = <Stroke>{};
    final elements = <SurfaceElement>{};
    _loaded.removeWhere((key) {
      if (keep.contains(key)) return false;
      evicted.add(key);
      strokes.addAll(_strokes.inChunk(key));
      elements.addAll(_elements.inChunk(key));
      return true;
    });
    bool stillNeeded(Rect bounds) => ChunkGrid.rangeFor(bounds).keys.any(_loaded.contains);
    for (final s in strokes) {
      if (stillNeeded(s.bounds) || _hidden.contains(s.id)) continue;
      _strokes.remove(s);
      evicted.addAll(ChunkGrid.rangeFor(s.bounds).keys);
    }
    for (final e in elements) {
      if (stillNeeded(e.bounds) || _hidden.contains(e.id)) continue;
      _elements.remove(e);
      evicted.addAll(ChunkGrid.rangeFor(e.bounds).keys);
    }
    // Nothing visible changed, so listeners need not be notified.
    if (evicted.isNotEmpty) _invalidations.add(evicted);
  }

  // ---------------------------------------------------------------------------
  // Editing

  /// Adds a newly drawn stroke (persisted immediately, undoable).
  void addStroke(Stroke stroke) => commit(InkEdit(added: [stroke]));

  /// Applies [edit] (persisted immediately) and records it for undo. With
  /// [merge], it joins the previous undo step (one continuous gesture).
  void commit(InkEdit edit, {bool merge = false}) {
    if (edit.isEmpty) return;
    _apply(edit);
    history.record(edit, merge: merge);
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
    final edit = history.takeUndo();
    if (edit != null) _apply(edit.inverse);
  }

  void redo() {
    final edit = history.takeRedo();
    if (edit != null) _apply(edit);
  }

  void _apply(InkEdit edit) {
    final changed = <ChunkKey>{};
    void touch(Rect bounds) => changed.addAll(ChunkGrid.rangeFor(bounds).keys);

    if (edit.removed.isNotEmpty) _repository.delete(edit.removed.map((s) => s.id));
    if (edit.added.isNotEmpty) _repository.save(edit.added);
    for (final s in edit.removed) {
      final current = _strokes[s.id];
      if (current != null) _strokes.remove(current);
      touch(s.bounds);
    }
    for (final s in edit.added) {
      _strokes.insert(s);
      touch(s.bounds);
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
        _elements.remove(current);
        touch(current.bounds);
      }
      touch(e.bounds);
    }
    for (final e in edit.addedElements) {
      _elements.insert(e);
      touch(e.bounds);
    }
    _changed(changed);
  }

  void _changed(Set<ChunkKey> chunks) {
    _invalidations.add(chunks);
    notifyListeners();
  }

  @override
  void dispose() {
    _invalidations.close();
    super.dispose();
  }
}
