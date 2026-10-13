import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/clock.dart';
import '../data/element_repository.dart';
import '../data/stroke_reader.dart';
import '../data/stroke_repository.dart';
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
import 'stroke_hit_test.dart';
import 'surface_change.dart';
import 'surface_loader.dart';
import 'undo_history.dart';

export 'lifted_content.dart';
export 'surface_change.dart';

part 'surface_model_editing.dart';
part 'surface_model_hiding.dart';
part 'surface_model_loading.dart';
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
/// (the working set following the viewport) and [_SurfaceEditing]
/// (undoable edits and their persistence).
class SurfaceModel extends _SurfaceState with _SurfaceHiding, _SurfaceLoading, _SurfaceEditing {
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
  });

  /// Populated chunks within [range] (in memory).
  List<ChunkKey> chunksIn(ChunkRange range) {
    final strokes = _strokes.populatedIn(range);
    final elements = _elements.populatedIn(range);
    if (elements.isEmpty) return strokes;
    return {...strokes, ...elements}.toList();
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
