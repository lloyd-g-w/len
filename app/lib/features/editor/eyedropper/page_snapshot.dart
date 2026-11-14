import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../../ink/images/image_pixel.dart';
import '../../../ink/render/raster_batch.dart';

/// The surface as shown when the eyedropper started, in device pixels: the
/// loupe enlarges it, and where no content gives a colour, its pixels do.
class PageSnapshot {
  PageSnapshot._(this.image, this._pixels, this.origin, this.dpr);

  /// Captures [boundary] (after the frame in progress), or null if it
  /// cannot be captured.
  static Future<PageSnapshot?> capture(RenderRepaintBoundary boundary, double dpr) async {
    try {
      await SchedulerBinding.instance.endOfFrame;
      if (!boundary.attached) return null;
      final origin = boundary.localToGlobal(Offset.zero);
      final image = await _capture(boundary, dpr);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (bytes == null) {
        image.dispose();
        return null;
      }
      return PageSnapshot._(image, bytes, origin, dpr);
    } catch (_) {
      return null; // Not painted (yet), or the view went.
    }
  }

  /// [boundary] as an image. In the JavaScript build in tile-sized
  /// slices ([RasterBatch.stitch]): the shared surface keeps its size.
  static Future<ui.Image> _capture(RenderRepaintBoundary boundary, double dpr) {
    final batch = RasterBatch.shared;
    if (!batch.batching) return boundary.toImage(pixelRatio: dpr);
    // What RenderRepaintBoundary.toImage draws, a part at a time.
    // ignore: invalid_use_of_protected_member
    final layer = boundary.layer! as OffsetLayer;
    final size = batch.atlasSize;
    // Just under [size] device pixels a slice, so rounding up keeps it there.
    final extent = (size - 0.01) / dpr;
    return batch.stitch(
      (boundary.size.width * dpr).ceil(),
      (boundary.size.height * dpr).ceil(),
      (left, top) =>
          layer.toImage(Rect.fromLTWH(left / dpr, top / dpr, extent, extent), pixelRatio: dpr),
    );
  }

  /// The captured pixels.
  final ui.Image image;
  final ByteData _pixels;

  /// Where the captured box's top left lies on screen (global).
  final Offset origin;

  /// Device pixels per logical pixel.
  final double dpr;

  /// [global] in [image]'s pixels.
  Offset toImage(Offset global) => (global - origin) * dpr;

  /// The colour shown at [global] (opaque ARGB); null outside the capture.
  int? pixelAt(Offset global) {
    final p = toImage(global);
    final x = p.dx.floor(), y = p.dy.floor();
    if (x < 0 || y < 0 || x >= image.width || y >= image.height) return null;
    final rgba = _pixels.getUint32((y * image.width + x) * 4);
    return ImagePixels.rgbaToArgb(rgba) | 0xFF000000;
  }

  void dispose() => image.dispose();
}
