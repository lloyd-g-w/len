import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../features/documents/scan/quad_detector.dart';
import '../features/documents/scan/scan_job.dart';

/// Renders [job]'s page on the UI thread, yielding between bands, and has
/// the browser encode it: encoding a page in Dart holds the UI thread for
/// half a second or more (`test/perf/scan_perf_test.dart`), the browser's
/// encoder runs off it. Falls back to Dart's where the browser can't.
Future<ScanOutput> runScanJob(ScanJob job) async {
  final page = await job.renderSliced(_yield);
  await _yield();
  final jpeg = await _browserJpeg(page, job.jpegQuality);
  if (jpeg == null) return job.encode(page);
  return ScanOutput(jpeg, page.width, page.height);
}

/// Renders [job]'s page (no encoding) on the UI thread, yielding between
/// bands, e.g. a thumbnail.
Future<RgbaImage> renderScanPreview(ScanJob job) => job.renderSliced(_yield);

/// The document's outline in [photo] (its pixels); null if there is no
/// convincing one. Detection works on a small copy: it runs in one go.
Future<Quad?> detectScanQuad(RgbaImage photo) async {
  await _yield();
  return QuadDetector.find(photo);
}

Future<void> _yield() => Future<void>.delayed(Duration.zero);

/// [page] as a JPEG of [quality] (1..100) from the browser's encoder, or
/// null if it has none (no `OffscreenCanvas`, or it failed).
Future<Uint8List?> _browserJpeg(RgbaImage page, int quality) async {
  try {
    final canvas = web.OffscreenCanvas(page.width, page.height);
    final context = canvas.getContext('2d') as web.OffscreenCanvasRenderingContext2D?;
    if (context == null) return null;
    final pixels = page.pixels;
    final clamped = Uint8ClampedList.view(pixels.buffer, pixels.offsetInBytes, pixels.length);
    context.putImageData(web.ImageData(clamped.toJS, page.width, page.height.toJS), 0, 0);
    final blob = await canvas
        .convertToBlob(web.ImageEncodeOptions(type: 'image/jpeg', quality: quality / 100))
        .toDart;
    if (blob.type != 'image/jpeg') return null; // Unsupported: it made a PNG.
    return (await blob.arrayBuffer().toDart).toDart.asUint8List();
  } on Object {
    return null;
  }
}
