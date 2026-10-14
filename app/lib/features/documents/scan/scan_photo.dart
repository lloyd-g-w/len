import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../ink/images/element_images.dart';
import '../../../platform/scan_runner.dart';
import 'scan_job.dart';

/// The photo could not be read as an image.
class ScanPhotoException implements Exception {
  const ScanPhotoException(this.message);

  final String message;

  @override
  String toString() => 'ScanPhotoException: $message';
}

/// A photo of a document, ready for the corner editor: its encoded bytes,
/// its size (upright, as the engine applies EXIF orientation), a small
/// working copy for previews and the outline found in it.
///
/// Quads are in [width] × [height] pixels of the whole photo, whatever
/// resolution it is decoded at.
class ScanPhoto {
  ScanPhoto._(this.bytes, this.width, this.height, this.work, this.detected);

  /// The long side of [work], in pixels.
  static const int workEdge = 800;

  /// The long side the photo is decoded at for the finished page: enough
  /// for a 2500-px page without wasting memory on a 50-MP photo.
  static const int sourceEdge = 3200;

  /// Reads [bytes] and looks for the document in it; throws
  /// [ScanPhotoException] if they are no image.
  static Future<ScanPhoto> load(Uint8List bytes) async {
    final int width, height;
    try {
      (:width, :height) = await ElementImages.measure(bytes);
    } on Object {
      throw const ScanPhotoException('Unsupported or damaged image');
    }
    if (width <= 0 || height <= 0) throw const ScanPhotoException('Empty image');
    final work = await decodeRgba(bytes, width, height, workEdge);
    final found = await detectScanQuad(work);
    final s = width / work.width;
    return ScanPhoto._(bytes, width, height, work, found?.scaled(s));
  }

  /// The encoded photo.
  final Uint8List bytes;

  /// Upright width in pixels.
  final int width;

  /// Upright height in pixels.
  final int height;

  /// The photo at most [workEdge] pixels on its long side.
  final RgbaImage work;

  /// The document's outline found in the photo, if any.
  final Quad? detected;

  /// The whole photo as a quad.
  Quad get bounds => Quad.bounds(width.toDouble(), height.toDouble());

  /// Where the corner editor starts: the document found, else the whole
  /// photo.
  Quad get initialQuad => detected ?? bounds;

  /// The photo decoded at most [maxEdge] pixels on its long side, for
  /// showing it.
  Future<ui.Image> decode(int maxEdge) =>
      ElementImages.decode(bytes, width: _widthFor(width, height, maxEdge));

  /// The photo as straight RGBA, at most [maxEdge] pixels on its long side.
  static Future<RgbaImage> decodeRgba(Uint8List bytes, int width, int height, int maxEdge) async {
    final image = await ElementImages.decode(bytes, width: _widthFor(width, height, maxEdge));
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (data == null) throw const ScanPhotoException('Cannot read image pixels');
      return RgbaImage(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        image.width,
        image.height,
      );
    } finally {
      image.dispose();
    }
  }

  /// A job flattening [quad] (photo pixels) of the full-resolution photo,
  /// turned [quarterTurns], cleaned up by [filter].
  Future<ScanJob> job(Quad quad, {required int quarterTurns, required ScanFilter filter}) async {
    final source = await decodeRgba(bytes, width, height, sourceEdge);
    return ScanJob(
      source: source,
      quad: quad.scaled(source.width / width).rotated(quarterTurns),
      filter: filter,
    );
  }

  /// A small job for a preview [maxEdge] pixels on its long side, from
  /// [work].
  ScanJob previewJob(
    Quad quad, {
    required int quarterTurns,
    required ScanFilter filter,
    required int maxEdge,
  }) => jobOn(work, quad, quarterTurns: quarterTurns, filter: filter, maxEdge: maxEdge);

  /// A job for a page [maxEdge] pixels on its long side, from [source]
  /// (this photo decoded at any size).
  ScanJob jobOn(
    RgbaImage source,
    Quad quad, {
    required int quarterTurns,
    required ScanFilter filter,
    required int maxEdge,
  }) => ScanJob(
    source: source,
    quad: quad.scaled(source.width / width).rotated(quarterTurns),
    filter: filter,
    maxEdge: maxEdge,
  );

  /// The decode width giving a long side of at most [maxEdge].
  static int _widthFor(int width, int height, int maxEdge) {
    final long = math.max(width, height);
    if (long <= maxEdge) return width;
    return math.max(1, (width * maxEdge / long).round());
  }
}
