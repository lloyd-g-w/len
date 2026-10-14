import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../platform/scan_runner.dart';
import 'scan_job.dart';
import 'scan_photo.dart';

/// [page] (straight RGBA) as an engine image.
Future<ui.Image> rgbaToImage(RgbaImage page) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    page.pixels,
    page.width,
    page.height,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}

/// One page's photo, outline, turns and look: what a rendering follows.
typedef ScanResultRequest = ({ScanPhoto photo, Quad quad, int turns, ScanFilter filter});

/// Renders one page at a time flattened and cleaned up at [edge] pixels
/// (the scan screen's large result), from its photo decoded at that size
/// (kept while the same photo is shown: it is re-rendered on every change).
/// The latest request wins; [onReady] hears each finished image.
class ScanResultRenderer {
  ScanResultRenderer({required this.edge, required this.onReady});

  /// The long side of the result (and of the photo it comes from).
  final int edge;
  final VoidCallback onReady;

  ({ScanResultRequest request, ui.Image image})? _shown;
  ({ScanPhoto photo, RgbaImage pixels})? _source;
  int _version = 0;
  bool _disposed = false;

  /// The latest image rendered of [photo] (perhaps of an earlier outline or
  /// look while a new one renders), if any.
  ui.Image? imageOf(ScanPhoto photo) => _shown?.request.photo == photo ? _shown?.image : null;

  /// Whether the latest image shows exactly [request].
  bool isCurrent(ScanResultRequest request) => _shown?.request == request;

  /// Renders [request] (in the background).
  void render(ScanResultRequest request) {
    final version = ++_version;
    unawaited(_render(request, version));
  }

  Future<void> _render(ScanResultRequest r, int version) async {
    final ui.Image image;
    try {
      var source = _source;
      if (source == null || source.photo != r.photo) {
        _source = null;
        final p = r.photo;
        final pixels = await ScanPhoto.decodeRgba(p.bytes, p.width, p.height, edge);
        if (_disposed || version != _version) return;
        source = _source = (photo: p, pixels: pixels);
      }
      final job = r.photo.jobOn(
        source.pixels,
        r.quad,
        quarterTurns: r.turns,
        filter: r.filter,
        maxEdge: edge,
      );
      image = await rgbaToImage(await renderScanPreview(job));
    } on Object catch (e) {
      debugPrint('Scan result failed: $e');
      return;
    }
    if (_disposed || version != _version) {
      image.dispose();
      return;
    }
    _shown?.image.dispose();
    _shown = (request: r, image: image);
    onReady();
  }

  /// Drops the image and the photo kept (the result is no longer shown).
  void clear() {
    _version++;
    _shown?.image.dispose();
    _shown = null;
    _source = null;
  }

  /// Drops everything for good.
  void dispose() {
    _disposed = true;
    clear();
  }
}
