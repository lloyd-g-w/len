part of 'surface_model.dart';

/// The working set following the viewport: chunks near it are read from
/// storage (their outlines prepared first, nearest the middle first), far
/// ones evicted again.
mixin _SurfaceLoading on _SurfaceState {
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

  @override
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

  @override
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
    if (evicted.isNotEmpty) _changes.add(SurfaceChange(evicted, evicted: true));
  }
}
