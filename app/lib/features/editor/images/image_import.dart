import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../../data/blob_mime.dart';
import '../../../data/blob_store.dart';
import '../../../domain/image_data.dart';
import '../../../ink/images/element_images.dart';

/// An image ready to be stored: encoded bytes and their natural size.
class PreparedImage {
  const PreparedImage(this.bytes, {required this.mime, required this.width, required this.height});

  final Uint8List bytes;
  final String mime;
  final int width;
  final int height;
}

/// The bytes could not be read as an image.
class ImageImportException implements Exception {
  const ImageImportException(this.message);

  final String message;

  @override
  String toString() => 'ImageImportException: $message';
}

/// Turns user-supplied image files into blobs that are light to sync.
///
/// PNG, JPEG and WebP files that are at most [maxEdge] pixels on their long
/// edge and [maxKeptBytes] in size are stored unchanged. Everything else —
/// larger images, GIFs (first frame), HEIC/HEIF and other formats the
/// platform can decode — is decoded (by the engine, off the UI thread),
/// downscaled to [maxEdge] and re-encoded in a background isolate: JPEG
/// when fully opaque, PNG when it has transparency.
abstract final class ImageImport {
  /// Longest edge (pixels) of a stored image.
  static const int maxEdge = 4096;

  /// Largest file stored without re-encoding.
  static const int maxKeptBytes = 8 << 20;

  /// JPEG quality of re-encoded photos.
  static const int jpegQuality = 88;

  /// Formats stored as they are (when small enough).
  static const Set<String> keptMimes = {'image/png', 'image/jpeg', 'image/webp'};

  /// File extensions offered by the file picker.
  static const List<String> extensions = [
    'png',
    'jpg',
    'jpeg',
    'webp',
    'gif',
    'bmp',
    'heic',
    'heif',
  ];

  /// The MIME type of encoded image [bytes] by their signature, or null.
  static String? sniff(Uint8List bytes) {
    final mime = BlobMime.sniff(bytes);
    return mime.startsWith('image/') ? mime : null;
  }

  /// Prepares [bytes] for storage (see class docs).
  static Future<PreparedImage> prepare(Uint8List bytes) async {
    final mime = sniff(bytes);
    final int width, height;
    try {
      (:width, :height) = await ElementImages.measure(bytes);
    } catch (_) {
      throw const ImageImportException('Unsupported or damaged image');
    }
    if (width <= 0 || height <= 0) throw const ImageImportException('Empty image');
    final keep =
        keptMimes.contains(mime) &&
        math.max(width, height) <= maxEdge &&
        bytes.length <= maxKeptBytes;
    if (keep) return PreparedImage(bytes, mime: mime!, width: width, height: height);
    return _reencode(bytes, width, height);
  }

  static Future<PreparedImage> _reencode(Uint8List bytes, int width, int height) async {
    final scale = math.min(1.0, maxEdge / math.max(width, height));
    final ui.Image image;
    try {
      image = await ElementImages.decode(bytes, width: math.max(1, (width * scale).round()));
    } catch (_) {
      throw const ImageImportException('Unsupported or damaged image');
    }
    try {
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (rgba == null) throw const ImageImportException('Cannot read image pixels');
      final encoded = await compute(_encode, (
        rgba: rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
        width: image.width,
        height: image.height,
      ));
      return PreparedImage(
        encoded.bytes,
        mime: encoded.mime,
        width: image.width,
        height: image.height,
      );
    } finally {
      image.dispose();
    }
  }

  /// Stores [image] in [blobs] and returns the element data referencing it.
  static Future<ImageData> store(BlobStore blobs, PreparedImage image) async {
    final sha = await blobs.putBytes(image.bytes, mime: image.mime);
    return ImageData(blob: sha, width: image.width, height: image.height);
  }
}

typedef _Pixels = ({Uint8List rgba, int width, int height});

/// Runs in a background isolate: JPEG for opaque pixels, else PNG.
({Uint8List bytes, String mime}) _encode(_Pixels p) {
  var opaque = true;
  for (var i = 3; i < p.rgba.length; i += 4) {
    if (p.rgba[i] != 0xFF) {
      opaque = false;
      break;
    }
  }
  final image = img.Image.fromBytes(
    width: p.width,
    height: p.height,
    bytes: p.rgba.buffer,
    bytesOffset: p.rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  if (opaque) {
    return (bytes: img.encodeJpg(image, quality: ImageImport.jpegQuality), mime: 'image/jpeg');
  }
  return (bytes: img.encodePng(image, level: 6), mime: 'image/png');
}
