import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../data/stroke_repository.dart';
import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';
import 'spatial_index.dart';
import 'stroke_hit_test.dart';
import 'undo_history.dart';

/// The in-memory working set of one drawing surface (a page or a canvas).
///
/// Only chunks near the viewport are loaded from storage; far-away chunks
/// are evicted again, so memory and render cost depend on what is on screen
/// rather than on the total amount of ink. Every edit is persisted
/// immediately, so the in-memory state is purely a cache plus undo history.
class SurfaceModel extends ChangeNotifier {
  SurfaceModel({
    required this.surfaceId,
    required this._repository,
    this.maxLoadedChunks = 1024,
  });

  final String surfaceId;
  final StrokeRepository _repository;

  /// Soft cap on loaded chunks before far-away ones are evicted.
  final int maxLoadedChunks;

  final Map<String, Stroke> _strokes = {};
  final SpatialIndex _index = SpatialIndex();

  /// Chunks whose stored content is fully in memory.
  final Set<ChunkKey> _loaded = {};

  final UndoHistory history = UndoHistory();

  final _invalidations = StreamController<Set<ChunkKey>?>.broadcast(sync: true);

  ChunkRange? _lastRange;
  Rect? _lastVisible;

  /// Emits chunks whose rendering is stale; `null` means "everything".
  Stream<Set<ChunkKey>?> get invalidations => _invalidations.stream;

  int get loadedStrokeCount => _strokes.length;

  // ---------------------------------------------------------------------------
  // Queries

  /// Populated chunks within [range] (in memory).
  List<ChunkKey> chunksIn(ChunkRange range) => _index.populatedIn(range);

  /// Strokes overlapping [key], in paint order.
  List<Stroke> strokesInChunk(ChunkKey key) =>
      [for (final id in _index.idsIn(key)) _strokes[id]!]..sort(Stroke.paintOrder);

  Stroke? strokeById(String id) => _strokes[id];

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

    final missing = _repository
        .populatedChunks(surfaceId, range)
        .where((key) => !_loaded.contains(key))
        .toList();
    if (missing.isNotEmpty) {
      final changed = <ChunkKey>{};
      for (final stroke in _repository.loadChunks(surfaceId, missing)) {
        if (_strokes.containsKey(stroke.id)) continue;
        _insert(stroke);
        changed.addAll(ChunkGrid.rangeFor(stroke.bounds).keys);
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
    _index.clear();
    _loaded.clear();
    _lastRange = null;
    _invalidations.add(null);
    final visible = _lastVisible;
    if (visible != null) ensureLoaded(visible);
    notifyListeners();
  }

  /// Unloads every chunk outside [keep]. A stroke stays in memory while any
  /// loaded chunk still needs it. Only the affected chunks are invalidated,
  /// so cached pictures of what is on screen survive.
  void _evictOutside(ChunkRange keep) {
    final evicted = <ChunkKey>{};
    final candidates = <String>{};
    _loaded.removeWhere((key) {
      if (keep.contains(key)) return false;
      evicted.add(key);
      candidates.addAll(_index.idsIn(key));
      return true;
    });
    for (final id in candidates) {
      final stroke = _strokes[id]!;
      final keys = ChunkGrid.rangeFor(stroke.bounds).keys;
      if (keys.any(_loaded.contains)) continue;
      _remove(stroke);
      evicted.addAll(keys);
    }
    // Nothing visible changed, so listeners need not be notified.
    if (evicted.isNotEmpty) _invalidations.add(evicted);
  }

  // ---------------------------------------------------------------------------
  // Editing

  /// Adds a newly drawn stroke (persisted immediately, undoable).
  void addStroke(Stroke stroke) {
    _repository.save([stroke]);
    _insert(stroke);
    history.record(InkEdit(added: [stroke]));
    _changed(ChunkGrid.rangeFor(stroke.bounds).keys.toSet());
  }

  /// Removes every stroke hit by the eraser sweeping from [a] to [b].
  /// Consecutive calls with [continueEdit] merge into one undo step.
  /// Returns whether anything was erased.
  bool eraseAlong(Offset a, Offset b, double radius, {required bool continueEdit}) {
    final sweep = Rect.fromPoints(a, b).inflate(radius);
    final hits = [
      for (final id in _index.query(sweep))
        if (StrokeHitTest.sweepHits(_strokes[id]!, a, b, radius)) _strokes[id]!,
    ];
    if (hits.isEmpty) return false;
    _repository.delete(hits.map((s) => s.id));
    final changed = <ChunkKey>{};
    for (final s in hits) {
      _remove(s);
      changed.addAll(ChunkGrid.rangeFor(s.bounds).keys);
    }
    history.record(InkEdit(removed: hits), merge: continueEdit);
    _changed(changed);
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
    if (edit.removed.isNotEmpty) _repository.delete(edit.removed.map((s) => s.id));
    if (edit.added.isNotEmpty) _repository.save(edit.added);
    final changed = <ChunkKey>{};
    for (final s in edit.removed) {
      final current = _strokes[s.id];
      if (current != null) _remove(current);
      changed.addAll(ChunkGrid.rangeFor(s.bounds).keys);
    }
    for (final s in edit.added) {
      _insert(s);
      changed.addAll(ChunkGrid.rangeFor(s.bounds).keys);
    }
    _changed(changed);
  }

  // ---------------------------------------------------------------------------
  // Internals

  void _insert(Stroke stroke) {
    final previous = _strokes[stroke.id];
    if (previous != null) _remove(previous);
    _strokes[stroke.id] = stroke;
    _index.insert(stroke.id, stroke.bounds);
  }

  void _remove(Stroke stroke) {
    _strokes.remove(stroke.id);
    _index.remove(stroke.id, stroke.bounds);
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
