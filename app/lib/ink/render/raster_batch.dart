import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// A picture made into pixels by [RasterBatch]: the whole of [image], or
/// the part of it at [source] when it shares an atlas with others.
class RasterImage {
  RasterImage(this.image, {ui.Rect? source, int? bytes})
    : source = source ?? ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      bytes = bytes ?? image.width * image.height * 4;

  /// The image holding the raster: a handle of its own (an atlas is
  /// freed once every raster on it is disposed).
  final ui.Image image;

  /// Where the raster is on [image].
  final ui.Rect source;

  /// Memory charged to the raster: its share of the atlas.
  final int bytes;

  /// The raster's size in pixels.
  int get width => source.width.round();
  int get height => source.height.round();

  /// Whether the raster is all of [image] (it can be stored or encoded).
  bool get whole => width == image.width && height == image.height;

  void dispose() => image.dispose();
}

/// Makes images of pictures ([rasterize]), for the raster caches (ink
/// tiles, level-of-detail rasters, page thumbnails).
///
/// Natively and in the WebAssembly build each is [ui.Picture.toImage],
/// rasterised off the UI thread. In the JavaScript build (CanvasKit)
/// every picture made into an image is drawn on a shared offscreen
/// surface and read back to the CPU at once, on the UI thread: a GPU
/// round trip each (~25 ms under software GL even for an empty picture),
/// and a resize of the surface whenever the size asked for changes
/// (~70 ms more). There ([batching]) the pictures asked for until an
/// atlas is full, or an event-loop turn passes without more, are drawn
/// side by side into an [atlasSize]² atlas — one read-back each, one
/// atlas a turn, the surface always the same size —
/// and each gets a handle of its own on its atlas with the part it
/// occupies. A picture as large as an atlas (an ink tile) or larger is
/// made at once, alone: queued, it would only wait behind others, and a
/// tile cache asks for the most urgent first.
class RasterBatch {
  RasterBatch({required this.batching, this.atlasSize = 512});

  /// The batch the raster caches share.
  static final RasterBatch shared = RasterBatch(batching: kIsWeb && !kIsWasm);

  /// Whether pictures are drawn into shared atlases (see the class doc).
  final bool batching;

  /// Edge of an atlas in pixels (the ink tiles' size, so tiles and
  /// atlases share one surface size).
  final int atlasSize;

  /// Rasters sit on an atlas at multiples of this many pixels, and as
  /// many apart: power-of-two rasters (level-of-detail rasters) on
  /// multiples of their size, so neither their mipmaps nor sampling a
  /// raster drawn smaller (as they are) reaches into a neighbour.
  /// Magnified, CanvasKit's sampling reaches up to half a pixel past a
  /// raster's edge.
  static const int _align = 4;

  static int _aligned(int pixels) => (pixels + _align - 1) ~/ _align * _align;

  final List<_Request> _queue = [];
  Timer? _timer;

  /// Read-backs made so far (atlases and pictures made alone; tests).
  @visibleForTesting
  int readbacks = 0;

  /// Rasterises [picture] (drawn from the origin) to [width] × [height]
  /// pixels. The picture must stay undisposed until the future completes.
  Future<RasterImage> rasterize(ui.Picture picture, int width, int height) {
    if (!batching ||
        width >= atlasSize && height >= atlasSize ||
        width > atlasSize ||
        height > atlasSize) {
      readbacks++;
      return picture.toImage(width, height).then(RasterImage.new);
    }
    final request = _Request(picture, width, height);
    _queue.add(request);
    _queued += _aligned(width) * _aligned(height);
    _arrived = true;
    _timer ??= Timer(Duration.zero, _flush);
    return request.done.future;
  }

  /// Area the queued pictures take on atlases.
  int _queued = 0;

  /// Whether pictures were asked for since the last check.
  bool _arrived = false;

  /// Draws the next atlas: the queued pictures that fit, tallest first,
  /// in rows.
  void _flush() {
    _timer = null;
    if (_queue.isEmpty) return;
    // Drawn once an atlas is full or a turn passes without more: makers
    // record a few pictures a turn.
    if (_arrived && _queued < atlasSize * atlasSize) {
      _arrived = false;
      _timer = Timer(Duration.zero, _flush);
      return;
    }
    _arrived = false;
    final placed = <(_Request, ui.Rect)>[];
    var x = 0, y = 0, row = 0;
    final candidates = [..._queue]..sort((a, b) => b.height.compareTo(a.height));
    for (final r in candidates) {
      if (x > 0 && x + r.width > atlasSize) {
        x = 0;
        y += row;
        row = 0;
      }
      if (y + r.height > atlasSize) continue; // Shorter ones may still fit.
      if (x + r.width > atlasSize) continue;
      placed.add((
        r,
        ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), r.width.toDouble(), r.height.toDouble()),
      ));
      x += _aligned(r.width);
      if (_aligned(r.height) > row) row = _aligned(r.height);
    }
    for (final (r, _) in placed) {
      _queue.remove(r);
      _queued -= _aligned(r.width) * _aligned(r.height);
    }
    if (_queue.isNotEmpty) _timer = Timer(Duration.zero, _flush);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    for (final (r, rect) in placed) {
      canvas
        ..save()
        ..translate(rect.left, rect.top)
        ..clipRect(ui.Offset.zero & rect.size)
        ..drawPicture(r.picture)
        ..restore();
    }
    final atlas = recorder.endRecording();
    readbacks++;
    // Always the same size, even for one small picture: a resize costs
    // more than the read-back (its memory is charged to the raster).
    unawaited(
      atlas
          .toImage(atlasSize, atlasSize)
          .then(
            (image) {
              if (placed.length == 1) {
                final (r, rect) = placed.single;
                return r.done.complete(RasterImage(image, source: rect));
              }
              final area = placed.fold(0.0, (sum, p) => sum + p.$2.width * p.$2.height);
              for (final (r, rect) in placed) {
                final share = (atlasSize * atlasSize * 4 * rect.width * rect.height / area).round();
                r.done.complete(RasterImage(image.clone(), source: rect, bytes: share));
              }
              image.dispose();
            },
            onError: (Object error, StackTrace stack) {
              for (final (r, _) in placed) {
                r.done.completeError(error, stack);
              }
            },
          )
          .whenComplete(atlas.dispose),
    );
  }
}

class _Request {
  _Request(this.picture, this.width, this.height);

  final ui.Picture picture;
  final int width;
  final int height;
  final Completer<RasterImage> done = Completer();
}
