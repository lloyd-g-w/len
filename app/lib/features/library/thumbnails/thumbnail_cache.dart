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
/// Renders run one per event-loop turn so a large library never blocks a
/// frame for long; listeners are notified as images arrive.
class ThumbnailCache extends ChangeNotifier {
  ThumbnailCache({required this.renderer, required this.stats, this.width = 320});

  final ThumbnailRenderer renderer;
  final SurfaceStats stats;

  /// Pixel width of rendered previews.
  final int width;

  /// Most entries kept; the least recently used are dropped beyond this.
  static const int capacity = 96;

  final LinkedHashMap<String, _Entry> _entries = LinkedHashMap();
  final LinkedHashMap<String, Notebook> _queue = LinkedHashMap();
  Timer? _timer;
  bool _disposed = false;

  /// The cached preview of [notebook] (null = plain cover), scheduling a
  /// refresh if its content may have changed since it was rendered.
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

  void _enqueue(Notebook notebook) {
    _queue[notebook.id] = notebook;
    _timer ??= Timer(Duration.zero, _processNext);
  }

  void _processNext() {
    _timer = null;
    if (_disposed || _queue.isEmpty) return;
    final notebook = _queue.remove(_queue.keys.first)!;
    if (_refresh(notebook)) notifyListeners();
    if (_queue.isNotEmpty) _timer = Timer(Duration.zero, _processNext);
  }

  /// Re-renders [notebook] if its fingerprint changed; true if the image did.
  bool _refresh(Notebook notebook) {
    final surface = renderer.previewSurfaceOf(notebook);
    final fingerprint = surface == null
        ? null
        : (surface: surface, paper: notebook.paper, stats: stats.fingerprint(surface));
    final old = _entries[notebook.id];
    if (old != null && old.fingerprint == fingerprint) {
      old
        ..checkedAt = notebook.updatedAt
        ..stale = false;
      return false;
    }
    ui.Image? image;
    try {
      image = fingerprint == null ? null : renderer.render(notebook, width: width);
    } on Object catch (e) {
      debugPrint('Thumbnail of ${notebook.id} failed: $e');
    }
    old?.image?.dispose();
    _entries[notebook.id] = _Entry(image, fingerprint, notebook.updatedAt);
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first)?.image?.dispose();
    }
    return true;
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
}
