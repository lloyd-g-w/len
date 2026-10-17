import 'dart:ui';

import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';

/// A change of what a surface renders: the [chunks] whose rendering is
/// stale (null: everything).
class SurfaceChange {
  const SurfaceChange(
    this.chunks, {
    this.appended,
    this.underlaid,
    this.overlaid,
    this.loaded = false,
    this.evicted = false,
    this.areas,
  });

  final Set<ChunkKey>? chunks;

  /// The world rectangles within [chunks] whose rendering changed (the
  /// bounds of the items edited), when known; null: all of [chunks].
  final List<Rect>? areas;

  /// Set when the change only appends these strokes on top of everything
  /// in [chunks] (pen ink, nothing above it there): a rendering of the
  /// chunks from before plus these strokes, in order, is up to date.
  final List<Stroke>? appended;

  /// Set when the change only adds these highlighter strokes, which paint
  /// beneath the pen ink: a rendering from before with them drawn beneath
  /// it looks as the live highlighter did (beneath the committed ink), so
  /// it may stand in until a new rendering is made.
  final List<Stroke>? underlaid;

  /// Set when the change only adds these strokes (or shows them again: a
  /// selection dropped), but they are no [appended] or [underlaid] ones:
  /// something in their chunks paints over them (a text box or an image
  /// above the ink, ink of a later paint order, say from another device),
  /// or they were drawn elsewhere (lifted by a selection, over the ink). A
  /// rendering from before with the pen strokes drawn over it and the
  /// highlighter ones beneath it looks as the live or lifted strokes did,
  /// so it may stand in until a new rendering is made — rather than the
  /// strokes vanishing until one is.
  final List<Stroke>? overlaid;

  /// Set when the change only brings in stored content (a load): a
  /// rendering from before may stand in until a new one is made, as the
  /// content was not on screen yet anyway (nothing the user did vanishes
  /// or lingers).
  final bool loaded;

  /// Set when the change only drops content from memory (an eviction):
  /// storage still holds it unchanged, so nothing about the surface's
  /// content changed (renderings of [chunks] made from memory are stale).
  final bool evicted;

  /// Whether the surface's content itself changed (an edit, a sync), not
  /// just what of it is in memory ([loaded], [evicted]).
  bool get altersContent => !loaded && !evicted;
}
