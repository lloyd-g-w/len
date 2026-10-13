import 'dart:math' as math;
import 'dart:ui';

import '../domain/chunk_grid.dart';

/// What each view of a surface needs in memory: a view either loads
/// everything around what it shows, or (zoomed far out, drawing stored
/// rasters) only the chunks asked for ([wanted]). Two panes of one canvas
/// — an overview and a close-up — each get what they need.
class SurfaceViews {
  final Map<Object?, _View> _views = {};

  /// Chunks views showing stored rasters asked to read (none stored).
  final Set<ChunkKey> wanted = {};

  /// The visible area of the view that moved last.
  Rect? lastVisible;

  /// Records that [view] shows [visible] and loads everything around it
  /// ([stored] false) or only [wanted] chunks. Returns the range to read
  /// for it, or null if nothing new is needed.
  ChunkRange? show(Object? view, Rect visible, {required bool stored}) {
    lastVisible = visible;
    final range = ChunkGrid.rangeFor(visible.inflate(ChunkGrid.size));
    final before = _views[view];
    _views[view] = _View(visible, range, stored: stored);
    if (stored) {
      wanted.removeWhere((key) => !keeps(key));
      return null;
    }
    return before != null && !before.stored && before.range == range ? null : range;
  }

  /// Forgets [view] (gone).
  void forget(Object? view) => _views.remove(view);

  /// Whether any view shows stored rasters.
  bool get anyStored => _views.values.any((v) => v.stored);

  /// [view]'s visible area if it shows stored rasters (it then needs to
  /// load it, see `SurfaceModel.loadVisible`).
  Rect? storedVisible(Object? view) {
    final v = _views[view];
    return v != null && v.stored ? v.visible : null;
  }

  /// The ranges views that load everything need (to read again after a
  /// reload).
  Iterable<ChunkRange> get loadedRanges => [
    for (final v in _views.values)
      if (!v.stored) v.range,
  ];

  /// Whether a read may skip [key]: no view loads everything around it
  /// and none asked for it. Without views, nothing is skipped.
  bool skips(ChunkKey key) =>
      _views.isNotEmpty &&
      !wanted.contains(key) &&
      !_views.values.any((v) => !v.stored && v.range.contains(key));

  /// Whether [key] is near a view (not to be evicted).
  bool keeps(ChunkKey key) => _views.values.any((v) => v.range.contains(key));

  /// The range covering [wanted].
  ChunkRange? get wantedRange {
    if (wanted.isEmpty) return null;
    final first = wanted.first;
    var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y;
    for (final k in wanted) {
      minX = math.min(minX, k.x);
      minY = math.min(minY, k.y);
      maxX = math.max(maxX, k.x);
      maxY = math.max(maxY, k.y);
    }
    return ChunkRange(minX, minY, maxX, maxY);
  }

  void clear() {
    wanted.clear();
    // Views stay: they are shown again after a reload.
  }
}

class _View {
  _View(this.visible, this.range, {required this.stored});

  final Rect visible;
  final ChunkRange range;
  final bool stored;
}
