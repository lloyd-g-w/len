import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import '../data/stroke_reader.dart';
import '../data/stroke_repository.dart';
import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';
import '../domain/stroke_chunks.dart';
import 'geometry/stroke_splitter.dart';
import 'pen/eraser_config.dart';
import 'spatial_index.dart';
import 'stroke_hit_test.dart';
import 'surface_loader.dart';
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
    StrokeReader? reader,
    this.maxLoadedChunks = 1024,
    this.clock = const Clock(),
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

  /// Soft cap on loaded chunks before far-away ones are evicted.
  final int maxLoadedChunks;

  final Map<String, Stroke> _strokes = {};
  final SpatialIndex _index = SpatialIndex();

  /// Chunks whose stored content is fully in memory.
  final Set<ChunkKey> _loaded = {};

  final UndoHistory history = UndoHistory();

  final _invalidations = StreamController<Set<ChunkKey>?>.broadcast(sync: true);

  late final SurfaceLoader _loading;
  bool _disposed = false;

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
  ///
  /// With a synchronous reader (the default) the chunks are loaded on
  /// return; with an asynchronous one they arrive later (see [isLoading]).
  void ensureLoaded(Rect visibleWorld) {
    if (visibleWorld.isEmpty || !visibleWorld.isFinite) return;
    _lastVisible = visibleWorld;
    final range = ChunkGrid.rangeFor(visibleWorld.inflate(ChunkGrid.size));
    if (range == _lastRange) return;
    _lastRange = range;
    _loading.request(range);
  }

  /// Whether chunks are still being read in the background.
  bool get isLoading => _loading.isLoading;

  /// Completes when no background read is pending.
  Future<void> get loaded => _loading.idle;

  Set<ChunkKey> _loadedWithin(ChunkRange range) => {
    for (final key in _loaded)
      if (range.contains(key)) key,
  };

  void _onLoad(ChunkLoad load) {
    if (_disposed) return;
    if (load.chunks.isNotEmpty) {
      final changed = <ChunkKey>{};
      for (final stroke in load.strokes) {
        if (_strokes.containsKey(stroke.id)) continue;
        _insert(stroke);
        changed.addAll(StrokeChunks.of(stroke));
      }
      _loaded.addAll(load.chunks);
      if (changed.isNotEmpty) _changed(changed);
    }
    final keep = _lastRange;
    if (keep != null && _loaded.length > maxLoadedChunks) _evictOutside(keep);
  }

  /// Drops everything in memory and reloads from storage (e.g. after a sync
  /// brought in remote changes).
  void reload() {
    _strokes.clear();
    _index.clear();
    _loaded.clear();
    _lastRange = null;
    _loading.reset();
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
      final keys = StrokeChunks.of(stroke);
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
    _changed(StrokeChunks.of(stroke));
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
    for (final id in _index.query(sweep)) {
      final stroke = _strokes[id]!;
      if (highlighterOnly && !stroke.tool.isHighlighter) continue;
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
    _repository.delete(removed.map((s) => s.id));
    if (added.isNotEmpty) _repository.save(added);
    final changed = <ChunkKey>{};
    for (final s in removed) {
      _remove(s);
      changed.addAll(StrokeChunks.of(s));
    }
    for (final s in added) {
      _insert(s);
    }
    history.record(
      InkEdit(added: added, removed: removed),
      merge: continueEdit,
    );
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
      changed.addAll(StrokeChunks.of(s));
    }
    for (final s in edit.added) {
      _insert(s);
      changed.addAll(StrokeChunks.of(s));
    }
    _changed(changed);
  }

  // ---------------------------------------------------------------------------
  // Internals

  void _insert(Stroke stroke) {
    final previous = _strokes[stroke.id];
    if (previous != null) _remove(previous);
    _strokes[stroke.id] = stroke;
    _index.insertAt(stroke.id, StrokeChunks.of(stroke));
  }

  void _remove(Stroke stroke) {
    _strokes.remove(stroke.id);
    _index.removeAt(stroke.id, StrokeChunks.of(stroke));
    _loading.noteRemoved(stroke.id);
  }

  void _changed(Set<ChunkKey> chunks) {
    _invalidations.add(chunks);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loading.dispose();
    _invalidations.close();
    super.dispose();
  }
}
