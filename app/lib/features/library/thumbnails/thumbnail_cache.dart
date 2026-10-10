import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../data/surface_stats.dart';
import '../../../domain/notebook.dart';
import 'thumbnail_renderer.dart';

/// In-memory cache of notebook preview images.
///
/// [imageFor] answers immediately with whatever is cached (possibly stale)
/// and queues a re-render when the notebook's content fingerprint changed.
/// Queued previews are rendered in short batches, one batch per event-loop
/// turn, so a large library never blocks a frame for long; listeners are
/// notified once per batch in which a preview changed.
class ThumbnailCache extends ChangeNotifier {
  ThumbnailCache({required this.renderer, required this.stats, this.width = 320});

  final ThumbnailRenderer renderer;
  final SurfaceStats stats;

  /// Pixel width of rendered previews.
  final int width;

  /// Most entries kept; the least recently used are dropped beyond this —
  /// but never one requested since the last notification (it is on screen:
  /// evicting it would dispose an image being shown and make it re-render
  /// on every rebuild).
  static const int capacity = 96;

  /// Time a batch may take before yielding to the event loop (a render
  /// always completes, so one dense page can still exceed it).
  static const Duration _batchBudget = Duration(milliseconds: 8);

  final LinkedHashMap<String, _Entry> _entries = LinkedHashMap();
  final LinkedHashMap<String, Notebook> _queue = LinkedHashMap();
  Timer? _timer;
  bool _disposed = false;

  /// Bumped on every notification; entries requested by the rebuild that
  /// follows carry the new value in [_Entry.usedIn].
  int _generation = 0;

  /// The cached preview of [notebook] (null = plain cover), scheduling a
  /// refresh if its content may have changed since it was rendered.
  ///
  /// Safe to call during build: it never notifies synchronously.
  ui.Image? imageFor(Notebook notebook) {
    final entry = _entries.remove(notebook.id);
    if (entry != null) {
      _entries[notebook.id] = entry..usedIn = _generation; // Mark recently used.
    }
    if (entry == null || entry.checkedAt != notebook.updatedAt || entry.stale) {
      _enqueue(notebook);
    }
    return entry?.image;
  }

  /// Forces previews of [notebookIds] (or all, when null) to be re-checked
  /// on next use — e.g. after an editor closed or strokes arrived by sync.
  void invalidate([Iterable<String>? notebookIds]) {
    final ids = notebookIds ?? _entries.keys.toList();
    for (final id in ids) {
      _entries[id]?.stale = true;
    }
    _notify();
  }

  void _enqueue(Notebook notebook) {
    if (_disposed) return;
    _queue[notebook.id] = notebook;
    _timer ??= Timer(Duration.zero, _processBatch);
  }

  void _processBatch() {
    _timer = null;
    if (_disposed) return;
    final watch = Stopwatch()..start();
    var changed = false;
    while (_queue.isNotEmpty && watch.elapsed < _batchBudget) {
      final notebook = _queue.remove(_queue.keys.first)!;
      changed |= _refresh(notebook);
    }
    if (_queue.isNotEmpty) _timer = Timer(Duration.zero, _processBatch);
    if (changed) _notify();
  }

  void _notify() {
    if (_disposed) return;
    _generation++;
    notifyListeners();
  }

  /// Re-renders [notebook] if its fingerprint changed; true if the image did.
  bool _refresh(Notebook notebook) {
    final source = renderer.sourceOf(notebook);
    final fingerprint = source == null
        ? null
        : (
            surface: source.surfaceId,
            paper: source.paper,
            page: source.page?.bounds.size,
            color: source.page?.paperColor,
            stats: stats.fingerprint(source.surfaceId),
          );
    final old = _entries[notebook.id];
    if (old != null && old.fingerprint == fingerprint) {
      old
        ..checkedAt = notebook.updatedAt
        ..stale = false;
      return false;
    }
    ui.Image? image;
    try {
      image = source == null ? null : renderer.render(notebook, width: width, source: source);
    } on Object catch (e) {
      debugPrint('Thumbnail of ${notebook.id} failed: $e');
    }
    final hadImage = old?.image != null;
    old?.image?.dispose();
    _entries[notebook.id] = _Entry(image, fingerprint, notebook.updatedAt)..usedIn = _generation;
    _evict();
    // Nothing drawn before or after: covers look the same, no rebuild.
    return hadImage || image != null;
  }

  /// Drops least recently used entries beyond [capacity] that are not on
  /// screen.
  void _evict() {
    var excess = _entries.length - capacity;
    if (excess <= 0) return;
    for (final id in _entries.keys.toList()) {
      final entry = _entries[id]!;
      if (entry.usedIn == _generation) continue;
      _entries.remove(id);
      entry.image?.dispose();
      if (--excess == 0) return;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final e in _entries.values) {
      e.image?.dispose();
    }
    _entries.clear();
    super.dispose();
  }
}

class _Entry {
  _Entry(this.image, this.fingerprint, this.checkedAt);

  final ui.Image? image;
  final Object? fingerprint;
  int checkedAt;
  bool stale = false;

  /// [ThumbnailCache._generation] when last requested.
  int usedIn = 0;
}
