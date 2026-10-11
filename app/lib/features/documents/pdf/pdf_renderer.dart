import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import '../../../data/blob_store.dart';

/// Opens PDF blobs with PDFium (via `pdfrx`) and renders their pages.
///
/// Documents stay open while in use; rendering is serialised because
/// PDFium is single-threaded anyway.
class PdfRenderer {
  PdfRenderer(this.blobs);

  /// Where the PDFs come from.
  final BlobStore blobs;

  final Map<String, Future<PdfDocument>> _documents = {};
  Future<void> _queue = Future.value();
  bool _disposed = false;

  static Future<void>? _initialized;

  /// Initialises PDFium once per process.
  static Future<void> ensureInitialized() => _initialized ??= pdfrxFlutterInitialize();

  /// Opens (or reuses) PDF blob [sha]: from its file where the platform
  /// has files (PDFium then reads it on demand), else from memory (web).
  Future<PdfDocument> open(String sha) => _documents[sha] ??= () async {
    await ensureInitialized();
    final path = blobs.localPath(sha);
    if (path != null) return PdfDocument.openFile(path);
    final bytes = await blobs.read(sha);
    if (bytes == null) throw StateError('PDF blob $sha is not available');
    return PdfDocument.openData(bytes, sourceName: 'blob:$sha');
  }();

  /// Renders page [index] of PDF blob [sha] at [pixelWidth] pixels wide on
  /// a white background. Requests whose [stillWanted] returns false by the
  /// time their turn comes are skipped.
  Future<ui.Image?> render(String sha, int index, int pixelWidth, {bool Function()? stillWanted}) {
    final result = _queue.then((_) async {
      if (_disposed || !(stillWanted?.call() ?? true)) return null;
      final doc = await open(sha);
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

  /// PDF blob [sha] rewritten by PDFium: decrypted (files that open without
  /// a password) and repaired, for Len's own PDF reader to copy pages from.
  /// Null if PDFium cannot open it either.
  Future<Uint8List?> normalized(String sha) => _serial(() async {
    if (_disposed) return null;
    return (await open(sha)).encodePdf(removeSecurity: true);
  });

  /// Runs [action] after every earlier PDFium request.
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Page sizes in PDF points (1/72 inch) of PDF blob [sha].
  Future<List<ui.Size>> pageSizes(String sha) async {
    final doc = await open(sha);
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
