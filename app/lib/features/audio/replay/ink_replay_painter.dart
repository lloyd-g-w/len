import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../domain/chunk_grid.dart';
import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/elements/element_renderer.dart';
import '../../../ink/render/stroke_renderer.dart';
import '../../../ink/surface_model.dart';
import 'replay_target.dart';

/// How strongly ink not yet written at the playback time is faded.
const double replayVeilOpacity = 0.82;

/// Fades ink, text boxes and images created after the moment being heard,
/// GoodNotes-style.
///
/// Drawn as a separate layer over the committed ink, only while a
/// recording is open, so normal rendering pays nothing. Each visible chunk
/// gets one cached picture of its "future" strokes filled in the paper
/// colour, composited at [replayVeilOpacity]; it is re-recorded only when
/// the set of future strokes in that chunk changes (a stroke's time is
/// passed, or the chunk is edited), so a frame of playback is a handful of
/// `drawPicture` calls.
class InkReplayPainter extends CustomPainter {
  InkReplayPainter({required this.target, required this.wallTime, required this.veils, this.until})
    : super(repaint: Listenable.merge([target.changes, wallTime]));

  final ReplayTarget target;

  /// The wall time (epoch ms) being heard; null paints nothing.
  final ValueListenable<int?> wallTime;
  final ReplayVeils veils;

  /// Content made after this wall time (after the kept audio of a trimmed
  /// recording) is not veiled; null veils everything after [wallTime].
  final int? until;

  @override
  void paint(Canvas canvas, Size size) {
    final now = wallTime.value;
    if (now == null) return;
    final viewport = target.viewport;
    final visible = viewport.visibleWorldFor(size);
    canvas
      ..save()
      ..translate(viewport.offset.dx, viewport.offset.dy)
      ..scale(viewport.scale);
    for (final surface in target.visible(size)) {
      final local = visible.shift(-surface.origin);
      final chunks = surface.model.chunksIn(ChunkGrid.rangeFor(local));
      if (chunks.isEmpty) continue;
      canvas
        ..save()
        ..translate(surface.origin.dx, surface.origin.dy);
      if (surface.clip case final clip?) canvas.clipRect(clip);
      for (final key in chunks) {
        final picture = veils.pictureFor(surface.model, key, now, surface.paper, until: until);
        if (picture != null) canvas.drawPicture(picture);
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(InkReplayPainter old) =>
      old.target != target || old.wallTime != wallTime || old.veils != veils || old.until != until;
}

/// Cached veil pictures per (surface, chunk); see [InkReplayPainter].
///
/// A veil covers the strokes *and* elements (text boxes, images) of a
/// chunk created after the moment being heard. Future elements beneath the
/// ink are veiled first and the past ink above them is cut back out, so
/// what was already written stays crisp over a picture inserted later.
class ReplayVeils {
  final Map<SurfaceModel, Map<ChunkKey, _Veil>> _veils = {};
  int _count = 0;

  /// Upper bound on cached pictures (beyond it everything is dropped and
  /// re-recorded on demand).
  static const int maxPictures = 600;

  /// The veil of chunk [key] of [model] at wall time [now], or null when
  /// nothing in it was created after [now] (and, given [until], not after
  /// that either).
  ui.Picture? pictureFor(SurfaceModel model, ChunkKey key, int now, Color paper, {int? until}) {
    bool veiled(int t) => t > now && (until == null || t <= until);
    var signature = paper.toARGB32();
    var future = 0;
    for (final s in model.strokesInChunk(key)) {
      if (veiled(s.createdAt) && !model.isHidden(s.id)) {
        signature = Object.hash(signature, s.id);
        future++;
      }
    }
    for (final e in model.elementsInChunk(key)) {
      if (veiled(e.createdAt) && !model.isHidden(e.id)) {
        // Elements keep their id when edited: the value tells edits apart.
        signature = Object.hash(signature, identityHashCode(e));
        future++;
      }
    }
    final chunks = _veils[model] ??= {};
    final cached = chunks[key];
    if (cached != null && cached.signature == signature && cached.future == future) {
      return cached.picture;
    }
    cached?.picture?.dispose();
    if (cached == null) _count++;
    if (_count > maxPictures) {
      clear();
      _veils[model] = chunks;
      _count = 1;
    }
    final picture = future == 0 ? null : _record(model, key, veiled, paper);
    chunks[key] = _Veil(signature, future, picture);
    return picture;
  }

  ui.Picture _record(SurfaceModel model, ChunkKey key, bool Function(int) veiled, Color paper) {
    final recorder = ui.PictureRecorder();
    final rect = ChunkGrid.rectOf(key);
    final canvas = Canvas(recorder)
      ..clipRect(rect, doAntiAlias: false)
      // One layer, so overlapping content fades evenly.
      ..saveLayer(rect, Paint()..color = Color.fromRGBO(0, 0, 0, replayVeilOpacity));
    final fill = Paint()..color = paper;
    final strokes = [
      for (final s in model.strokesInChunk(key))
        if (!model.isHidden(s.id)) s,
    ];
    final elements = [
      for (final e in model.elementsInChunk(key))
        // Links are invisible: nothing to veil.
        if (veiled(e.createdAt) && !model.isHidden(e.id) && e.knownType != ElementType.link) e,
    ]..sort(SurfaceElement.paintOrder);
    final below = elements.where((e) => e.belowInk).toList();
    if (below.isNotEmpty) {
      for (final e in below) {
        _silhouette(canvas, e, rect, paper);
      }
      // Ink already written over a later picture stays visible.
      final cut = Paint()..blendMode = BlendMode.dstOut;
      for (final s in strokes) {
        if (!veiled(s.createdAt)) _silhouetteOf(canvas, s, cut);
      }
    }
    for (final s in strokes) {
      if (veiled(s.createdAt)) _silhouetteOf(canvas, s, fill);
    }
    for (final e in elements) {
      if (!e.belowInk) _silhouette(canvas, e, rect, paper);
    }
    canvas.restore();
    return recorder.endRecording();
  }

  /// Paints [s]'s ink, and the fill of a filled shape, with [paint].
  static void _silhouetteOf(Canvas canvas, Stroke s, Paint paint) {
    if (s.fill != null) canvas.drawPath(StrokeRenderer.fillPathOf(s), paint);
    canvas.drawPath(StrokeRenderer.pathOf(s), paint);
  }

  /// Paints [e]'s shape in [paper]: the (rotated) box of an image, the
  /// glyphs (and highlights) of a text box.
  static void _silhouette(Canvas canvas, SurfaceElement e, Rect chunk, Color paper) {
    if (e.knownType != ElementType.text) {
      canvas.drawPath(Path()..addPolygon(e.corners, true), Paint()..color = paper);
      return;
    }
    canvas.saveLayer(chunk, Paint());
    ElementRenderer.draw(canvas, e);
    canvas
      ..drawRect(
        chunk,
        Paint()
          ..color = paper
          ..blendMode = BlendMode.srcIn,
      )
      ..restore();
  }

  /// Drops every cached picture.
  void clear() {
    for (final chunks in _veils.values) {
      for (final v in chunks.values) {
        v.picture?.dispose();
      }
      chunks.clear();
    }
    _veils.clear();
    _count = 0;
  }
}

class _Veil {
  _Veil(this.signature, this.future, this.picture);

  final int signature;
  final int future;
  final ui.Picture? picture;
}
