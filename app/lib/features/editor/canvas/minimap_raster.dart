import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/elements/element_renderer.dart';
import '../../../ink/images/element_images.dart';
import '../../../ink/render/stroke_renderer.dart';
import 'minimap_sketch.dart';

/// An image of the content and the world area it shows.
class MinimapImage {
  MinimapImage(this.image, this.world);

  final ui.Image image;
  final Rect world;

  void dispose() => image.dispose();
}

/// The minimap's miniature: images of the world areas the map shows, the
/// [overview] (the whole map) and, while the map is zoomed in, a sharper
/// [detail] of the part shown. Painting the map draws an image or two,
/// however much the canvas holds.
///
/// The images are made from one picture per [MinimapSketch] tile, recorded
/// again only when its items change (or the scale moves to another power
/// of two: strokes are drawn at least [minLine] pixels wide, so a word on
/// a vast canvas still shows).
class MinimapRaster {
  MinimapRaster({this.images});

  /// Decoded bitmaps for image elements (placeholders without).
  final ElementImages? images;

  final _TilePictures _overviewTiles = _TilePictures();
  final _TilePictures _detailTiles = _TilePictures();
  MinimapImage? _overview;
  MinimapImage? _detail;
  int _generation = 0;
  bool _disposed = false;

  /// An image of the whole map, or null before the first.
  MinimapImage? get overview => _overview;

  /// A sharper image of the part a zoomed-in map shows.
  MinimapImage? get detail => _detail;

  /// Thinnest a stroke is drawn, in pixels.
  static const double minLine = 0.8;

  /// Image bitmaps are drawn at this many pixels per world unit at most.
  static const double imageScale = 0.5;

  /// Takes [sketch]'s changed tiles: their pictures are recorded again.
  void sync(MinimapSketch sketch) {
    final dirty = sketch.takeDirty();
    _overviewTiles.invalidate(dirty);
    _detailTiles.invalidate(dirty);
  }

  /// Makes the [overview] image of [world], [pixels] large, and the
  /// [detail] of [zoomed] when given (else drops it). Tile pictures are
  /// recorded a slice of time at a time ([slice]), yielding in between.
  Future<void> render(MinimapSketch sketch, Rect world, Size pixels, {Rect? zoomed}) async {
    final generation = ++_generation;
    bool superseded() => _disposed || generation != _generation;
    await _prepare(sketch, _overviewTiles, world, pixels, superseded);
    if (zoomed != null) await _prepare(sketch, _detailTiles, zoomed, pixels, superseded);
    if (superseded()) return;
    if (zoomed == null) _detailTiles.clear();
    final overview = _image(sketch, _overviewTiles, world, pixels);
    final detail = zoomed == null ? null : _image(sketch, _detailTiles, zoomed, pixels);
    final o = await overview;
    final d = await detail;
    if (superseded()) {
      o?.dispose();
      d?.dispose();
      return;
    }
    _overview?.dispose();
    _detail?.dispose();
    _overview = o;
    _detail = d;
  }

  /// Longest stretch of recording tile pictures before yielding.
  static const Duration slice = Duration(milliseconds: 6);

  /// Records the pictures [world] needs at [pixels] that [tiles] lacks.
  Future<void> _prepare(
    MinimapSketch sketch,
    _TilePictures tiles,
    Rect world,
    Size pixels,
    bool Function() superseded,
  ) async {
    if (world.isEmpty || pixels.isEmpty) return;
    tiles.scaleFor(pixels.width / world.width);
    // Items reach out of their tile (they belong to it by their centre).
    final near = world.inflate(MinimapSketch.tileSide);
    final watch = Stopwatch()..start();
    for (final tile in sketch.tiles.toList()) {
      if (tiles.has(tile) || !MinimapSketch.rectOf(tile).overlaps(near)) continue;
      if (watch.elapsed > slice) {
        await Future<void>.delayed(Duration.zero);
        if (superseded()) return;
        watch.reset();
      }
      tiles.put(tile, _record(sketch.itemsOf(tile), tiles.scale));
    }
  }

  Future<MinimapImage?>? _image(
    MinimapSketch sketch,
    _TilePictures tiles,
    Rect world,
    Size pixels,
  ) {
    final width = pixels.width.round(), height = pixels.height.round();
    if (width < 1 || height < 1 || world.isEmpty) return null;
    final scale = width / world.width;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..translate(-world.left, -world.top);
    for (final t in tiles.all) {
      if (t.bounds.overlaps(world)) canvas.drawPicture(t.picture);
    }
    final picture = recorder.endRecording();
    return picture
        .toImage(width, height)
        .then((i) => MinimapImage(i, world))
        .whenComplete(picture.dispose);
  }

  /// A tile's picture at [scale] pixels per world unit (a power of two):
  /// the editor's layers (elements beneath the ink, highlighter, ink,
  /// elements above), strokes as plain lines in their colours.
  _TilePicture? _record(
    ({List<Stroke> strokes, List<SurfaceElement> elements}) items,
    double scale,
  ) {
    if (items.strokes.isEmpty && items.elements.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final ink = [...items.strokes]..sort(Stroke.drawOrder);
    final elements = [...items.elements]..sort(SurfaceElement.paintOrder);
    final pixelScale = math.min(scale, imageScale);
    var bounds = ink.isNotEmpty ? ink.first.bounds : elements.first.bounds;
    void drawElements(bool below) {
      for (final e in elements) {
        if (e.belowInk != below) continue;
        ElementRenderer.draw(canvas, e, images: images, pixelScale: pixelScale);
        bounds = bounds.expandToInclude(e.bounds);
      }
    }

    drawElements(true);
    final thinnest = minLine / scale;
    for (final s in ink) {
      _sketch(canvas, s, math.max(s.width, thinnest));
      bounds = bounds.expandToInclude(s.bounds);
    }
    drawElements(false);
    return (picture: recorder.endRecording(), bounds: bounds.inflate(thinnest));
  }

  static void _sketch(Canvas canvas, Stroke s, double width) {
    StrokeRenderer.drawFill(canvas, s);
    final paint = StrokeRenderer.paintFor(s.color, s.style);
    final points = s.points;
    if (points.length < 2) {
      canvas.drawCircle(points.first.offset, width / 2, paint);
      return;
    }
    final path = Path()..moveTo(points.first.x, points.first.y);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].x, points[i].y);
    }
    canvas.drawPath(
      path,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void dispose() {
    _disposed = true;
    _overviewTiles.clear();
    _detailTiles.clear();
    _overview?.dispose();
    _detail?.dispose();
    _overview = _detail = null;
  }
}

typedef _TilePicture = ({ui.Picture picture, Rect bounds});

/// Tile pictures recorded for one scale (a power of two).
class _TilePictures {
  final Map<MinimapTile, _TilePicture?> _pictures = {};
  double scale = 0;

  /// Moves to the power of two at or below [pixelsPerUnit], dropping the
  /// pictures of another.
  void scaleFor(double pixelsPerUnit) {
    final level = math.pow(2, (math.log(pixelsPerUnit) / math.ln2).floor()).toDouble();
    if (level == scale) return;
    clear();
    scale = level;
  }

  bool has(MinimapTile tile) => _pictures.containsKey(tile);

  void put(MinimapTile tile, _TilePicture? picture) => _pictures[tile] = picture;

  /// The pictures recorded (tiles with nothing left hold none).
  Iterable<_TilePicture> get all => _pictures.values.nonNulls;

  void invalidate(Set<MinimapTile> tiles) {
    for (final tile in tiles) {
      _pictures.remove(tile)?.picture.dispose();
    }
  }

  void clear() {
    for (final t in _pictures.values) {
      t?.picture.dispose();
    }
    _pictures.clear();
  }
}
