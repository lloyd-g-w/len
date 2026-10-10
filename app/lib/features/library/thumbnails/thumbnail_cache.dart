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
  ThumbnailCache({required this.renderer, required this.stats, this.width = 320}) {
    _imageChanges = renderer.images?.changes.listen(_onImage);
  }

  final ThumbnailRenderer renderer;
  final SurfaceStats stats;

  /// Pixel width of rendered previews.
  final int width;

  /// Most entries kept; the least recently used are dropped beyond this.
  static const int capacity = 96;

  /// Time a batch may take before yielding to the event loop (a render
  /// always completes, so one dense page can still exceed it).
  static const Duration _batchBudget = Duration(milliseconds: 8);

  final LinkedHashMap<String, _Entry> _entries = LinkedHashMap();
  final LinkedHashMap<String, Notebook> _queue = LinkedHashMap();
  Timer? _timer;
  bool _disposed = false;

  /// Notebooks whose preview shows a placeholder for an image (by blob)
  /// that was still decoding.
  final Map<String, Set<String>> _waitingFor = {};
  StreamSubscription<String>? _imageChanges;

  /// The cached preview of [notebook] (null = plain cover), scheduling a
  /// refresh if its content may have changed since it was rendered.
  ///
  /// Safe to call during build: it never notifies synchronously.
  ui.Image? imageFor(Notebook notebook) {
    final entry = _entries.remove(notebook.id);
    if (entry != null) _entries[notebook.id] = entry; // Mark recently used.
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
    if (!_disposed) notifyListeners();
  }

  /// An image finished decoding: previews drawn without it render again.
  void _onImage(String blob) {
    final ids = _waitingFor.remove(blob);
    if (ids == null || _disposed) return;
    for (final id in ids) {
      _entries[id]
        ?..fingerprint = null
        ..stale = true;
    }
    notifyListeners();
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
    if (changed) notifyListeners();
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
      for (final blob in renderer.pendingImages) {
        (_waitingFor[blob] ??= {}).add(notebook.id);
      }
    } on Object catch (e) {
      debugPrint('Thumbnail of ${notebook.id} failed: $e');
    }
    final hadImage = old?.image != null;
    old?.image?.dispose();
    _entries[notebook.id] = _Entry(image, fingerprint, notebook.updatedAt);
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first)?.image?.dispose();
    }
    // Nothing drawn before or after: covers look the same, no rebuild.
    return hadImage || image != null;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_imageChanges?.cancel());
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

  /// What the preview was rendered from; null forces a new render.
  Object? fingerprint;
  int checkedAt;
  bool stale = false;
}
