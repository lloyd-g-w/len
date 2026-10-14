import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'scan_enhance.dart';
import 'scan_geometry.dart';
import 'scan_warp.dart';

export 'scan_enhance.dart' show ScanFilter;
export 'scan_geometry.dart';
export 'scan_image.dart';

/// A finished scanned page: JPEG bytes and their pixel size.
class ScanOutput {
  /// Wraps an encoded page.
  const ScanOutput(this.jpeg, this.width, this.height);

  /// The page as a JPEG.
  final Uint8List jpeg;

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;
}

/// One page to flatten: the photo, the document's outline in it, and how to
/// render it. Holds only sendable data, so it can run on a worker isolate.
class ScanJob {
  /// A job flattening [quad] of [source] to a page whose long side is at
  /// most [maxEdge] pixels, cleaned up by [filter] (as photographed if
  /// null).
  ScanJob({
    required this.source,
    required this.quad,
    this.filter,
    this.maxEdge = 2500,
    this.jpegQuality = 85,
  });

  /// The photo.
  final RgbaImage source;

  /// The document's corners in [source] pixels.
  final Quad quad;

  /// The document look (white paper, crisp ink), if any.
  final ScanFilter? filter;

  /// The page's longest side in pixels, at most.
  final int maxEdge;

  /// JPEG quality, 1..100.
  final int jpegQuality;

  /// Flattens (and enhances) the page in one go.
  RgbaImage render() {
    final r = _Render(this);
    r.warp(0, r.page.height);
    r.startEnhance();
    r.enhance(0, r.page.height);
    return r.page;
  }

  /// [render] in bands of [rowsPerSlice] rows, awaiting [yieldNow] between
  /// them (keeps a single-threaded UI responsive).
  Future<RgbaImage> renderSliced(Future<void> Function() yieldNow, {int rowsPerSlice = 64}) async {
    final r = _Render(this);
    final h = r.page.height;
    for (var y = 0; y < h; y += rowsPerSlice) {
      r.warp(y, math.min(h, y + rowsPerSlice));
      await yieldNow();
    }
    if (filter == null) return r.page;
    r.startEnhance();
    await yieldNow();
    for (var y = 0; y < h; y += rowsPerSlice) {
      r.enhance(y, math.min(h, y + rowsPerSlice));
      await yieldNow();
    }
    return r.page;
  }

  /// Renders and encodes the page.
  ScanOutput run() => encode(render());

  /// [run] in slices (see [renderSliced]); the encoding runs in one go.
  Future<ScanOutput> runSliced(Future<void> Function() yieldNow, {int rowsPerSlice = 64}) async {
    final page = await renderSliced(yieldNow, rowsPerSlice: rowsPerSlice);
    await yieldNow();
    return encode(page);
  }

  /// Encodes [page] as a JPEG of [jpegQuality].
  ScanOutput encode(RgbaImage page) =>
      ScanOutput(encodeJpeg(page, quality: jpegQuality), page.width, page.height);
}

/// [image] as a JPEG of [quality] (1..100), alpha dropped.
Uint8List encodeJpeg(RgbaImage image, {required int quality}) => img.encodeJpg(
  img.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: image.pixels.buffer,
    bytesOffset: image.pixels.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  ),
  quality: quality,
);

/// The state of one rendering: the page and the maps building it.
class _Render {
  _Render(this.job) {
    final size = job.quad.outputSize(maxEdge: job.maxEdge);
    page = RgbaImage.blank(size.width.toInt(), size.height.toInt());
    pageToSrc = Homography.pageToQuad(size, job.quad);
  }

  final ScanJob job;
  late final RgbaImage page;
  late final Homography pageToSrc;
  EnhanceMap? _map;

  void warp(int y0, int y1) => warpRows(job.source, pageToSrc, page, y0, y1);

  void startEnhance() {
    if (job.filter != null) _map = EnhanceMap.of(page);
  }

  void enhance(int y0, int y1) {
    final map = _map;
    if (map != null) enhanceRows(page, map, y0, y1, filter: job.filter!);
  }
}
