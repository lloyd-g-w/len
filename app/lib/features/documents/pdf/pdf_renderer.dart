import 'dart:async';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

/// Opens PDF blobs with PDFium (via `pdfrx`) and renders their pages.
///
/// Documents stay open while in use; rendering is serialised because
/// PDFium is single-threaded anyway.
class PdfRenderer {
  final Map<String, Future<PdfDocument>> _documents = {};
  Future<void> _queue = Future.value();
  bool _disposed = false;

  static Future<void>? _initialized;

  /// Initialises PDFium once per process.
  static Future<void> ensureInitialized() => _initialized ??= pdfrxFlutterInitialize();

  /// Opens (or reuses) the PDF at [path], identified by [key].
  Future<PdfDocument> open(String key, String path) => _documents[key] ??= () async {
    await ensureInitialized();
    return PdfDocument.openFile(path);
  }();

  /// Renders page [index] of document [key] (opened from [path]) at
  /// [pixelWidth] pixels wide on a white background. Requests whose
  /// [stillWanted] returns false by the time their turn comes are skipped.
  Future<ui.Image?> render(
    String key,
    String path,
    int index,
    int pixelWidth, {
    bool Function()? stillWanted,
  }) {
    final result = _queue.then((_) async {
      if (_disposed || !(stillWanted?.call() ?? true)) return null;
      final doc = await open(key, path);
      if (index >= doc.pages.length) return null;
      final page = doc.pages[index];
      final width = pixelWidth.toDouble();
      final height = (width * page.height / page.width).roundToDouble();
      final image = await page.render(
        fullWidth: width,
        fullHeight: height,
        backgroundColor: 0xFFFFFFFF,
      );
      if (image == null) return null;
      try {
        return await image.createImage();
      } finally {
        image.dispose();
      }
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Page sizes in PDF points (1/72 inch) of document [key].
  Future<List<ui.Size>> pageSizes(String key, String path) async {
    final doc = await open(key, path);
    return [for (final p in doc.pages) ui.Size(p.width, p.height)];
  }

  Future<void> dispose() async {
    _disposed = true;
    final docs = _documents.values.toList();
    _documents.clear();
    for (final d in docs) {
      try {
        await (await d).dispose();
      } catch (_) {
        // Failed to open in the first place.
      }
    }
  }
}
