import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import '../../../data/blob_store.dart';
import '../../../data/search/pdf_text_source.dart' show pdfiumRectToDisplay;
import '../../../domain/pdf_page_space.dart';

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
  Future<ui.Image?> render(String sha, int index, int pixelWidth, {bool Function()? stillWanted}) =>
      _serial(() async {
        if (_disposed || !(stillWanted?.call() ?? true)) return null;
        final doc = await open(sha);
        if (index >= doc.pages.length) return null;
        final page = doc.pages[index];
        final width = pixelWidth.toDouble();
        final height = (width * page.height / page.width).roundToDouble();
        return _image(
          await page.render(fullWidth: width, fullHeight: height, backgroundColor: _white),
        );
      });

  /// Renders the part ([x], [y], [width], [height]; pixels) of page [index]
  /// of PDF blob [sha] rendered [fullWidth] × [fullHeight] pixels: one tile
  /// for deep zoom. Skipped like [render] when no longer [stillWanted].
  Future<ui.Image?> renderArea(
    String sha,
    int index, {
    required int fullWidth,
    required int fullHeight,
    required int x,
    required int y,
    required int width,
    required int height,
    bool Function()? stillWanted,
  }) => _serial(() async {
    if (_disposed || !(stillWanted?.call() ?? true)) return null;
    final doc = await open(sha);
    if (index >= doc.pages.length) return null;
    final image = await doc.pages[index].render(
      x: x,
      y: y,
      width: width,
      height: height,
      fullWidth: fullWidth.toDouble(),
      fullHeight: fullHeight.toDouble(),
      backgroundColor: _white,
    );
    return _image(image);
  });

  static const _white = 0xFFFFFFFF;

  static Future<ui.Image?> _image(PdfImage? image) async {
    if (image == null) return null;
    try {
      return await image.createImage();
    } finally {
      image.dispose();
    }
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

  /// The links of page [index] of PDF blob [sha] (annotations and web
  /// addresses found in its text), normalised to the page as shown.
  Future<List<PdfLinkArea>> links(String sha, int index) async {
    final doc = await open(sha);
    if (index >= doc.pages.length) return const [];
    final p = doc.pages[index];
    if (p.width <= 0 || p.height <= 0) return const [];
    return [
      for (final link in await p.loadLinks())
        if (link.url != null || link.dest != null)
          PdfLinkArea(
            [for (final r in link.rects) pdfiumRectToDisplay(r, p)],
            page: link.dest == null ? null : link.dest!.pageNumber - 1,
            url: link.url,
          ),
    ];
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
