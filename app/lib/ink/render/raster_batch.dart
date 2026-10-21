import 'dart:async';
import 'dart:math' as math;
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

  /// In the JavaScript build, readies the shared surface while the app
  /// starts: sized for tiles and atlases (it starts at 1 × 1) and the
  /// programs ink tiles draw with compiled (filled and stroked paths,
  /// rectangles, images), each a GPU round trip of 0.1–0.3 s under
  /// software GL that would otherwise come with the first ink shown.
  Future<void> warmUp() async {
    if (!batching) return;
    final path = ui.Path()
      ..moveTo(20, 20)
      ..cubicTo(80, 0, 120, 90, 200, 40)
      ..lineTo(210, 60)
      ..quadraticBezierTo(120, 110, 18, 30)
      ..close();
    final ink = ui.Paint()..color = const ui.Color(0xFF202020);
    var recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..drawPath(path, ink)
      ..drawPath(
        path,
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = ui.StrokeCap.round
          ..color = const ui.Color(0x80FFEB3B),
      )
      ..drawRect(const ui.Rect.fromLTWH(10, 120, 60, 30), ink)
      ..drawCircle(const ui.Offset(120, 150), 6, ink);
    var picture = recorder.endRecording();
    final ui.Image image;
    try {
      readbacks++;
      image = await picture.toImage(atlasSize, atlasSize);
    } finally {
      picture.dispose();
    }
    await Future<void>.delayed(Duration.zero);
    recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..drawImage(image, ui.Offset.zero, ui.Paint()..filterQuality = ui.FilterQuality.none)
      ..drawImageRect(
        image,
        const ui.Rect.fromLTWH(0, 0, 256, 256),
        const ui.Rect.fromLTWH(256, 256, 128, 128),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
    picture = recorder.endRecording();
    try {
      readbacks++;
      (await picture.toImage(atlasSize, atlasSize)).dispose();
    } finally {
      picture.dispose();
      image.dispose();
    }
  }

  /// An image of [picture] (drawn from the origin) of its own, exactly
  /// [width] × [height] pixels: for callers that keep whole images
  /// (library covers, history previews) or read their pixels (exports,
  /// copies, colour picking).
  ///
  /// Natively and in WebAssembly this is [ui.Picture.toImage]. In the
  /// JavaScript build the shared surface is never resized for it (a resize
  /// cost 0.15–0.4 s under software GL, and as much again to go back to
  /// the tiles' size): a picture that fits an atlas is drawn on one
  /// ([rasterize]) and its pixels copied out on the CPU (the atlas is a
  /// CPU image there); a larger one is drawn in atlas-sized slices, one
  /// read-back an event-loop turn, and stitched. The picture must stay
  /// undisposed until the future completes.
  Future<ui.Image> image(ui.Picture picture, int width, int height) async {
    if (!batching) return picture.toImage(width, height);
    if (width == atlasSize && height == atlasSize) {
      readbacks++;
      return picture.toImage(width, height);
    }
    if (width <= atlasSize && height <= atlasSize) {
      return _cut(await rasterize(picture, width, height));
    }
    return stitch(width, height, (left, top) async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
        ..translate(-left.toDouble(), -top.toDouble())
        ..drawPicture(picture);
      final slice = recorder.endRecording();
      try {
        readbacks++;
        return await slice.toImage(atlasSize, atlasSize);
      } finally {
        slice.dispose();
      }
    });
  }

  /// [image] where the caller can't wait: natively and in WebAssembly
  /// [ui.Picture.toImageSync] (an image at once), in the JavaScript build
  /// [image] (later, without resizing the shared surface).
  FutureOr<ui.Image> imageNow(ui.Picture picture, int width, int height) =>
      batching ? image(picture, width, height) : picture.toImageSync(width, height);

  /// A [width] × [height] image put together from [atlasSize]² slices,
  /// [slice] giving the one whose top left is at (`left`, `top`); one a
  /// turn. Their pixels are copied on the CPU (images made of pictures
  /// are CPU images in the JavaScript build).
  Future<ui.Image> stitch(
    int width,
    int height,
    Future<ui.Image> Function(int left, int top) slice,
  ) async {
    final pixels = Uint8List(width * height * 4);
    for (var top = 0; top < height; top += atlasSize) {
      for (var left = 0; left < width; left += atlasSize) {
        if (left + top > 0) await Future<void>.delayed(Duration.zero);
        final image = await slice(left, top);
        try {
          final data = await image.toByteData();
          if (data == null) throw StateError('No pixels of a slice');
          _copy(
            data,
            image.width,
            left,
            top,
            math.min(atlasSize, width - left),
            math.min(atlasSize, height - top),
            pixels,
            width,
          );
        } finally {
          image.dispose();
        }
      }
    }
    return _fromPixels(pixels, width, height);
  }

  /// [raster] as an image of its own.
  static Future<ui.Image> _cut(RasterImage raster) async {
    if (raster.whole) return raster.image;
    try {
      final data = await raster.image.toByteData();
      if (data == null) throw StateError('No pixels of an atlas');
      final pixels = Uint8List(raster.width * raster.height * 4);
      _copy(
        data,
        raster.image.width,
        -raster.source.left.round(),
        -raster.source.top.round(),
        raster.width,
        raster.height,
        pixels,
        raster.width,
      );
      return await _fromPixels(pixels, raster.width, raster.height);
    } finally {
      raster.dispose();
    }
  }

  /// Copies [width] × [height] pixels from [from] (rows of [fromWidth]
  /// pixels, RGBA) to [to] (rows of [toWidth]), from's origin landing at
  /// ([left], [top]) of [to]: negative to take a part further in.
  static void _copy(
    ByteData from,
    int fromWidth,
    int left,
    int top,
    int width,
    int height,
    Uint8List to,
    int toWidth,
  ) {
    final source = from.buffer.asUint8List(from.offsetInBytes, from.lengthInBytes);
    final x0 = math.max(0, -left), y0 = math.max(0, -top);
    final dx = math.max(0, left), dy = math.max(0, top);
    for (var y = 0; y < height; y++) {
      final start = ((y0 + y) * fromWidth + x0) * 4;
      final at = ((dy + y) * toWidth + dx) * 4;
      to.setRange(at, at + width * 4, source, start);
    }
  }

  static Future<ui.Image> _fromPixels(Uint8List pixels, int width, int height) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
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
