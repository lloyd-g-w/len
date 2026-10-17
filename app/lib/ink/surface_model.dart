import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/clock.dart';
import '../data/element_repository.dart';
import '../data/raster_store.dart';
import '../data/stroke_reader.dart';
import '../data/stroke_repository.dart';
import '../domain/chunk_digest.dart';
import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';
import '../domain/stroke_chunks.dart';
import '../domain/surface_element.dart';
import 'content_index.dart';
import 'geometry/stroke_splitter.dart';
import 'images/element_images.dart';
import 'lifted_content.dart';
import 'pen/eraser_config.dart';
import 'render/outline_preparer.dart';
import 'scribble_hits.dart';
import 'stroke_hit_test.dart';
import 'surface_change.dart';
import 'surface_loader.dart';
import 'surface_views.dart';
import 'undo_history.dart';

export 'lifted_content.dart';
export 'surface_change.dart';

part 'surface_model_editing.dart';
part 'surface_model_hiding.dart';
part 'surface_model_loading.dart';
part 'surface_model_reload.dart';
part 'surface_model_state.dart';

/// The in-memory working set of one drawing surface (a page or a canvas):
/// its strokes and elements (text boxes).
///
/// Only chunks near the viewport are loaded from storage; far-away chunks
/// are evicted again, so memory and render cost depend on what is on screen
/// rather than on the total amount of content. Every edit is persisted
/// immediately, so the in-memory state is purely a cache plus undo history.
///
/// The model's parts: [_SurfaceState] (what it holds), [_SurfaceHiding]
/// (content shown elsewhere while selected or edited), [_SurfaceLoading]
/// (the working set following the viewport), [_SurfaceReload] (taking in
/// changes made beneath it) and [_SurfaceEditing]
/// (undoable edits and their persistence).
class SurfaceModel extends _SurfaceState
    with _SurfaceHiding, _SurfaceLoading, _SurfaceReload, _SurfaceEditing {
  SurfaceModel({
    required super.surfaceId,
    required super.repository,
    super.elementRepository,
    super.images,
    super.reader,
    super.maxLoadedChunks,
    super.clock,
    super.writeBehind,
    super.outlines,
    super.rasterStore,
  });

  /// Populated chunks within [range] (in memory).
  List<ChunkKey> chunksIn(ChunkRange range) {
    final strokes = _strokes.populatedIn(range);
    final elements = _elements.populatedIn(range);
    if (elements.isEmpty) return strokes;
    return {...strokes, ...elements}.toList();
  }

  /// Whether everything stored in [key] is in memory.
  bool isComplete(ChunkKey key) => _loaded.contains(key) && !_arriving.contains(key);

  /// The digest of [key]'s content when it is all in memory, not empty
  /// and drawn as stored: none hidden (selected, being edited). Null
  /// otherwise. (Images are content-addressed: an element's value names
  /// its blob by hash. Whether they are decoded yet is the renderer's
  /// business, see `ChunkPictureCache.isSettled`.)
  ChunkDigest? digestOf(ChunkKey key) {
    if (!isComplete(key)) return null;
    final strokes = _strokes.inChunk(key);
    final elements = _elements.inChunk(key);
    if (_hidden.isNotEmpty &&
        (strokes.any((s) => _hidden.contains(s.id)) ||
            elements.any((e) => _hidden.contains(e.id)))) {
      return null;
    }
    final digest = ChunkDigest.of(strokes, elements);
    return digest.strokes + digest.elements == 0 ? null : digest; // Emptied.
  }

  /// The digests of the populated chunks within [range] as stored (after
  /// writing pending edits).
  FutureOr<Map<ChunkKey, ChunkDigest>> storedDigests(ChunkRange range) {
    flush();
    return _loading.reader.chunkDigests(surfaceId, range);
  }

  /// Strokes overlapping [key], in paint order.
  List<Stroke> strokesInChunk(ChunkKey key) =>
      _strokes.inChunk(key).toList()..sort(Stroke.paintOrder);

  /// Elements overlapping [key], in stacking order.
  List<SurfaceElement> elementsInChunk(ChunkKey key) =>
      _elements.inChunk(key).toList()..sort(SurfaceElement.paintOrder);

  /// Candidate strokes whose chunks overlap [rect] (no precise test).
  Iterable<Stroke> strokesNear(Rect rect) => _strokes.query(rect);

  /// Elements whose bounds overlap [rect].
  Iterable<SurfaceElement> elementsNear(Rect rect) =>
      _elements.query(rect).where((e) => e.bounds.overlaps(rect));

  Stroke? strokeById(String id) => _strokes[id];
  SurfaceElement? elementById(String id) => _elements[id];

  /// The highest element stacking order loaded (for "new on top").
  double get topZ {
    var top = 0.0;
    for (final e in _elements.all) {
      if (e.z > top) top = e.z;
    }
    return top;
  }

  /// The lowest element stacking order loaded, at most 0.
  double get bottomZ {
    var bottom = 0.0;
    for (final e in _elements.query(Rect.largest)) {
      if (e.z < bottom) bottom = e.z;
    }
    return bottom;
  }

  /// The highest stacking order among loaded elements beneath the ink.
  double? get topBelowInkZ {
    double? top;
    for (final e in _elements.query(Rect.largest)) {
      if (e.belowInk && (top == null || e.z > top)) top = e.z;
    }
    return top;
  }

  /// Most items [refreshItems] takes on; more reload the surface.
  static const maxRefreshItems = 500;

  /// Brings in what sync changed of the strokes and elements [ids] (on this
  /// surface, or moved away from it) without reloading the rest, so a
  /// stroke written on another device appears on its own, with nothing
  /// else redrawn (live sync). Reloads instead when that cannot be told
  /// apart from what the surface does meanwhile: many items, a load under
  /// way, or one of them hidden (selected, being edited).
  void refreshItems(Set<String> ids) {
    if (_disposed || ids.isEmpty) return;
    if (ids.length > maxRefreshItems ||
        isLoading ||
        (_hidden.isNotEmpty && ids.any(_hidden.contains))) {
      reload();
      return;
    }
    flush();
    final list = ids.toList();
    final strokes = _repository.queries.strokesByIds(surfaceId, list);
    final elements = _elementRepository == null
        ? const <SurfaceElement>[]
        : _repository.queries.elementsByIds(surfaceId, list);
    bool shown(Iterable<ChunkKey> keys) => keys.any((k) => _loaded.contains(k) || _views.keeps(k));
    final added = [
      for (final s in strokes)
        if (shown(StrokeChunks.of(s))) s,
    ];
    final addedElements = [
      for (final e in elements)
        if (shown(ElementChunks.of(e))) e,
    ];
    final changed = <ChunkKey>{};
    final areas = <Rect>[];
    var removed = false;
    for (final id in ids) {
      if (_strokes[id] case final old?) {
        _removeStroke(old);
        changed.addAll(StrokeChunks.of(old));
        areas.add(old.bounds);
        removed = true;
      }
      if (_elements[id] case final old?) {
        _removeElement(old);
        changed.addAll(ElementChunks.of(old));
        areas.add(old.bounds);
        removed = true;
      }
    }
    final appended = !removed && _isAppend(InkEdit(added: added, addedElements: addedElements));
    for (final s in added) {
      _strokes.insert(s);
      changed.addAll(StrokeChunks.of(s));
      areas.add(s.bounds);
    }
    for (final e in addedElements) {
      _elements.insert(e);
      changed.addAll(ElementChunks.of(e));
      areas.add(e.bounds);
    }
    if (changed.isNotEmpty) _changed(changed, appended: appended ? added : null, areas: areas);
  }

  /// Drops the undo and redo steps (a restore rewrote the surface beneath
  /// them: undoing would take out what is gone, redoing write back what
  /// was replaced).
  void forgetHistory() {
    if (_disposed || !(history.canUndo || history.canRedo)) return;
    history.clear();
    notifyListeners();
  }

  /// [flush]es every surface, before code that reads or rewrites stored
  /// strokes directly (page copies and deletions, exports).
  static void flushAll() {
    for (final model in List.of(_withUnsaved)) {
      model.flush();
    }
  }

  @override
  void dispose() {
    flush();
    _disposed = true;
    _loading.dispose();
    _lifted.dispose();
    _changes.close();
    super.dispose();
  }
}
