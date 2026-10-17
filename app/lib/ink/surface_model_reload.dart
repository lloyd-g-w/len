part of 'surface_model.dart';

/// Reloading what is in memory from storage (after a sync wrote remote
/// changes beneath the views), in place: what is shown stays until the
/// stored content has arrived, which then replaces it in one change that
/// covers only the items that differ.
///
/// Dropping everything and reading it again instead left the surface
/// empty while the read ran (a worker isolate natively, so frames or
/// more): every remote change blanked the page being written on.
mixin _SurfaceReload on _SurfaceLoading {
  /// The reload in flight (null: none): newer ones replace it.
  Object? _reloadToken;

  /// Drops nothing, reads what the views show from storage again and swaps
  /// in what differs (e.g. after a sync brought in remote changes).
  void reload() {
    flush();
    _generation++; // Loads in flight predate the change.
    _loading.reset();
    _arriving.clear();
    final ranges = [..._views.loadedRanges, ?_views.wantedRange];
    _views.clear();
    if (ranges.isEmpty) return _dropAllLoaded();
    var range = ranges.first;
    for (final r in ranges.skip(1)) {
      range = ChunkRange(
        math.min(range.minX, r.minX),
        math.min(range.minY, r.minY),
        math.max(range.maxX, r.maxX),
        math.max(range.maxY, r.maxY),
      );
    }
    final skip = _views.anyStored
        ? {
            for (final key in range.keys)
              if (_views.skips(key)) key,
          }
        : const <ChunkKey>{};
    final token = _reloadToken = Object();
    if (_reloadEdits == null) _preparing++;
    _reloadEdits = {};
    void done() {
      if (_reloadToken != token) return;
      _reloadToken = null;
      _reloadEdits = null;
      _preparing--;
      if (_preparing == 0) _removedWhilePreparing.clear();
    }

    final FutureOr<ChunkLoad> read;
    try {
      read = _loading.reader.read(surfaceId, range, skip: skip);
    } on Object catch (error, stack) {
      done();
      return FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
    }
    Future<void> swap(ChunkLoad load) async {
      if (_disposed || _reloadToken != token) return;
      final outlines = this.outlines;
      if (outlines != null && load.strokes.isNotEmpty) {
        await outlines.prepare([
          for (final s in load.strokes)
            if (!_strokes.containsId(s.id)) s,
        ]);
        if (_disposed || _reloadToken != token) return;
      }
      _swapIn(load, (key) => range.contains(key) && !skip.contains(key));
      done();
    }

    if (read is ChunkLoad) {
      unawaited(swap(read));
    } else {
      read.then(
        swap,
        onError: (Object error, StackTrace stack) {
          done();
          FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
        },
      );
    }
  }

  /// Replaces what is in memory of the chunks [read] picks with [load]
  /// (what storage holds of them), keeping items edited here since the
  /// reload began; chunks not read are unloaded.
  void _swapIn(ChunkLoad load, bool Function(ChunkKey key) read) {
    final edited = _reloadEdits ?? const <String>{};
    final changed = <ChunkKey>{};
    final areas = <Rect>[];
    final strokes = {for (final s in load.strokes) s.id: s};
    final elements = {for (final e in load.elements) e.id: e};
    final gone = [
      for (final s in _strokes.all)
        if (!strokes.containsKey(s.id) && !edited.contains(s.id) && StrokeChunks.of(s).any(read)) s,
    ];
    for (final s in gone) {
      _removeStroke(s);
      changed.addAll(StrokeChunks.of(s));
      areas.add(s.bounds);
    }
    for (final s in load.strokes) {
      if (_strokes.containsId(s.id) || edited.contains(s.id)) continue;
      _strokes.insert(s);
      changed.addAll(StrokeChunks.of(s));
      areas.add(s.bounds);
    }
    if (_elementRepository != null) {
      final stale = [
        for (final e in _elements.all)
          if (!edited.contains(e.id) &&
              ElementChunks.of(e).any(read) &&
              !_sameElement(e, elements[e.id]))
            e,
      ];
      for (final e in stale) {
        _removeElement(e);
        changed.addAll(ElementChunks.of(e));
        areas.add(e.bounds);
      }
      for (final e in load.elements) {
        if (_elements.containsId(e.id) || edited.contains(e.id)) continue;
        _elements.insert(e);
        changed.addAll(ElementChunks.of(e));
        areas.add(e.bounds);
      }
    }
    _loaded.removeWhere(read);
    _loaded.addAll(load.chunks);
    // What was loaded beyond the views is read again when shown.
    _evictWhere((key) => !read(key));
    if (changed.isNotEmpty) _changed(changed, areas: areas);
  }

  static bool _sameElement(SurfaceElement a, SurfaceElement? b) =>
      b != null &&
      a.type == b.type &&
      a.rect == b.rect &&
      a.rotation == b.rotation &&
      a.z == b.z &&
      a.createdAt == b.createdAt &&
      jsonEncode(a.data) == jsonEncode(b.data);

  /// No view shows anything: everything goes, read again when shown.
  void _dropAllLoaded() {
    if (_reloadEdits != null) {
      _reloadEdits = null;
      _preparing--;
    }
    _reloadToken = null;
    _strokes.clear();
    _elements.clear();
    _loaded.clear();
    _changes.add(const SurfaceChange(null));
    notifyListeners();
  }
}
