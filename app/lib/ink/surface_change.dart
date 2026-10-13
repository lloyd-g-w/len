import 'dart:ui';

import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';

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
