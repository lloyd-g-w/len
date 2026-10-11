import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../app_services.dart';
import '../../../data/surface_copier.dart';
import '../../../domain/image_data.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/surface_model.dart';
import '../../editor/document/page_painting.dart';
import '../pdf/pdf_renderer.dart';
import 'pdf_export.dart';
import 'pdf_page_sources.dart';

/// The phases of a PDF export.
enum ExportStage { preparing, writing }

/// Hears that [done] of [total] pages went through [stage].
typedef ExportProgress = void Function(ExportStage stage, int done, int total);

/// Produces PDF and PNG files from notebook pages.
class NotebookExporter {
  NotebookExporter(this.services, {PdfRenderer? renderer})
    : _renderer = renderer ?? PdfRenderer(services.blobs),
      _copier = SurfaceCopier(services.strokes, elements: services.elements);

  final AppServices services;
  final PdfRenderer _renderer;
  final SurfaceCopier _copier;

  /// Resolution of PDF pages embedded as images (only pages that cannot be
  /// copied as vectors).
  static const double backgroundDpi = 150;

  /// A PDF of [pages] (vector ink and templates; imported PDF pages copied
  /// as vectors). [onProgress] hears how many pages are prepared, then
  /// written, and may throw to abandon the export. Without [backgrounds],
  /// imported PDF pages are left out. [onRasterized] hears the index (in
  /// [pages]) of each PDF page that had to be embedded as an image.
  Future<Uint8List> pdf(
    List<NotebookPage> pages, {
    String? title,
    ExportProgress? onProgress,
    bool backgrounds = true,
    void Function(int index)? onRasterized,
  }) async {
    SurfaceModel.flushAll(); // Ink drawn a moment ago.
    final sources = PdfPageSources(read: _readBlob, normalize: _renderer.normalized);
    final export = <ExportPage>[];
    for (final page in pages) {
      onProgress?.call(ExportStage.preparing, export.length, pages.length);
      export.add(
        ExportPage(
          page,
          _copier.loadAll(page.id),
          elements: _copier.loadAllElements(page.id),
          background: backgrounds ? await _exportBackground(page, sources) : null,
        ),
      );
    }
    return PdfExporter.build(
      export,
      title: title,
      onPage: (done) => onProgress?.call(ExportStage.writing, done, export.length),
      readBlob: _readBlob,
      onRasterized: onRasterized,
    );
  }

  Future<ExportBackground?> _exportBackground(NotebookPage page, PdfPageSources sources) async {
    final bg = page.background;
    if (bg == null || !await services.sync.fetchBlob(bg.blob)) return null;
    return ExportBackground(
      source: await sources.sourceOf(bg.blob),
      pageIndex: bg.pageIndex,
      raster: () => _background(page, page.width / 96 * backgroundDpi),
    );
  }

  /// A PNG of [page] at [scale] pixels per page unit (2 ≈ 192 dpi);
  /// without [backgrounds], an imported PDF page is left out (an image
  /// template stays: it is the page's paper).
  Future<Uint8List> png(NotebookPage page, {double scale = 2, bool backgrounds = true}) async {
    SurfaceModel.flushAll(); // Ink drawn a moment ago.
    final paperOnly = page.background == null && page.paper.image != null;
    final background = backgrounds || paperOnly
        ? await _background(page, page.width * scale)
        : null;
    final elements = _copier.loadAllElements(page.id);
    // Decode images first: painting only uses what is ready.
    for (final e in elements.where((e) => e.knownType == ElementType.image)) {
      final data = ImageData.fromJson(e.data);
      await services.images.load(data, e.rect.width * scale / data.crop.width);
    }
    final image = await renderPageImage(
      page,
      strokes: _copier.loadAll(page.id),
      elements: elements,
      scale: scale,
      background: background,
      images: services.images,
    );
    background?.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<Uint8List?> _readBlob(String sha) async =>
      await services.sync.fetchBlob(sha) ? services.blobs.read(sha) : null;

  Future<ui.Image?> _background(NotebookPage page, double pixelWidth) async {
    final bg = page.background;
    final template = page.paper.image;
    if (bg == null && template != null) {
      // An image template: exported like a background (a copy, as the
      // caller disposes it).
      final image = ImageData(blob: template, width: 0, height: 0);
      return (await services.images.load(image, pixelWidth))?.clone();
    }
    if (bg == null || !await services.sync.fetchBlob(bg.blob)) return null;
    return _renderer.render(bg.blob, bg.pageIndex, pixelWidth.round());
  }

  Future<void> dispose() => _renderer.dispose();
}
