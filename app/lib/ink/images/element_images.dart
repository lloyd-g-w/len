import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../domain/image_data.dart';

typedef _Key = ({String blob, int width});

/// Decoded bitmaps of image elements, shared by every view of the app.
///
/// Images are decoded asynchronously (the engine decodes off the UI
/// thread) at a width matching how large they are drawn — a mip level, a
/// power of two between [minWidth] and the image's natural width — and
/// kept in a least-recently-used cache within [budgetBytes]. [imageFor]
/// never blocks: it answers with the best bitmap available now (or null)
/// and schedules the decode; [changes] then reports the blob, so whoever
/// drew a stand-in can redraw. Blobs not yet on this device are fetched
/// through [fetch]; ones that cannot be had are reported by [isMissing].
class ElementImages {
  ElementImages({required this.read, required this.fetch, this.budgetBytes = 192 << 20});

  /// Reads a blob's bytes; null when it is not stored locally.
  final Future<Uint8List?> Function(String sha) read;

  /// Downloads a blob; returns whether it is available now.
  final Future<bool> Function(String sha) fetch;

  /// Memory budget for decoded bitmaps (4 bytes per pixel).
  final int budgetBytes;

  /// Smallest and largest decode widths.
  static const int minWidth = 64;
  static const int maxWidth = 4096;

  final LinkedHashMap<_Key, ui.Image> _images = LinkedHashMap();
  final Map<_Key, Future<ui.Image?>> _pending = {};
  final Set<String> _missing = {};
  final _changes = StreamController<String>.broadcast();
  int _bytes = 0;
  bool _disposed = false;

  /// Blobs whose best available bitmap (or missing state) changed.
  Stream<String> get changes => _changes.stream;

  /// Bytes held by cached bitmaps.
  int get bytes => _bytes;

  /// The decode width for drawing an image of natural width [natural]
  /// about [pixelWidth] device pixels wide.
  static int bucketFor(double pixelWidth, int natural) {
    final cap = natural > 0 ? math.min(natural, maxWidth) : maxWidth;
    if (!pixelWidth.isFinite || pixelWidth <= minWidth) return math.min(minWidth, cap);
    final level = 1 << (math.log(pixelWidth) / math.ln2).ceil();
    return math.min(level, cap);
  }

  /// The best bitmap of [image] to draw about [pixelWidth] device pixels
  /// wide (the whole image, before cropping), or null if none is decoded
  /// yet. Schedules a decode when nothing sharp enough is cached. Safe to
  /// call while painting: it never notifies synchronously.
  ui.Image? imageFor(ImageData image, double pixelWidth) {
    if (image.blob.isEmpty) return null;
    final width = bucketFor(pixelWidth, image.width);
    final key = (blob: image.blob, width: width);
    final exact = _images.remove(key);
    if (exact != null) return _images[key] = exact; // Most recently used.
    final best = _best(image.blob, width);
    if (best == null || best.width < width) _start(key);
    return best;
  }

  /// Whether [imageFor] has a bitmap of [image] sharp enough for drawing
  /// it [pixelWidth] device pixels wide (it then draws the same pixels
  /// every time).
  bool isSharp(ImageData image, double pixelWidth) {
    final width = bucketFor(pixelWidth, image.width);
    return _images.keys.any((k) => k.blob == image.blob && k.width >= width);
  }

  /// Decodes [image] for drawing [pixelWidth] pixels wide (fetching the
  /// blob if needed), e.g. before exporting. Null if it is unavailable.
  Future<ui.Image?> load(ImageData image, double pixelWidth) async {
    if (image.blob.isEmpty) return null;
    final now = imageFor(image, pixelWidth);
    final key = (blob: image.blob, width: bucketFor(pixelWidth, image.width));
    final pending = _pending[key];
    if (pending == null) return now;
    return await pending ?? now;
  }

  /// Whether [blob] could neither be read nor fetched (or not decoded).
  bool isMissing(String blob) => _missing.contains(blob);

  /// Forgets which blobs were unavailable, e.g. after a sync.
  void retryMissing() {
    final missing = _missing.toList();
    _missing.clear();
    missing.forEach(_emit);
  }

  /// The smallest cached bitmap at least [width] wide, else the largest.
  ui.Image? _best(String blob, int width) {
    ui.Image? above, below;
    for (final entry in _images.entries) {
      if (entry.key.blob != blob) continue;
      final w = entry.key.width;
      if (w >= width) {
        if (above == null || w < above.width) above = entry.value;
      } else if (below == null || w > below.width) {
        below = entry.value;
      }
    }
    return above ?? below;
  }

  void _start(_Key key) {
    if (_disposed || _missing.contains(key.blob) || _pending.containsKey(key)) return;
    // (A block body: returning the removed future would await itself.)
    _pending[key] = _decode(key).whenComplete(() {
      _pending.remove(key);
    });
  }

  Future<ui.Image?> _decode(_Key key) async {
    try {
      var bytes = await read(key.blob);
      if (bytes == null && await fetch(key.blob)) bytes = await read(key.blob);
      if (_disposed) return null;
      if (bytes == null) {
        _markMissing(key.blob);
        return null;
      }
      final image = await decode(bytes, width: key.width);
      if (_disposed) {
        image.dispose();
        return null;
      }
      _images[key]?.dispose();
      _images[key] = image;
      _bytes += _sizeOf(image);
      _evict(keep: key);
      _emit(key.blob);
      return image;
    } catch (e) {
      debugPrint('Cannot decode image ${key.blob}: $e');
      _markMissing(key.blob);
      return null;
    }
  }

  void _markMissing(String blob) {
    if (_missing.add(blob)) _emit(blob);
  }

  void _emit(String blob) {
    if (!_disposed) _changes.add(blob);
  }

  void _evict({required _Key keep}) {
    while (_bytes > budgetBytes && _images.length > 1) {
      final oldest = _images.keys.firstWhere((k) => k != keep);
      final image = _images.remove(oldest)!;
      _bytes -= _sizeOf(image);
      image.dispose();
    }
  }

  static int _sizeOf(ui.Image image) => image.width * image.height * 4;

  /// Decodes the first frame of an encoded image, scaled to [width] pixels
  /// wide (never wider than the image itself).
  static Future<ui.Image> decode(Uint8List bytes, {int? width}) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    buffer.dispose();
    try {
      final target = width == null || width >= descriptor.width ? null : width;
      final codec = await descriptor.instantiateCodec(targetWidth: target);
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  }

  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _bytes = 0;
    unawaited(_changes.close());
  }
}
