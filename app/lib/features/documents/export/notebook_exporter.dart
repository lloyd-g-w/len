import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../app_services.dart';
import '../../../data/surface_copier.dart';
import '../../../domain/image_data.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/surface_element.dart';
import '../../editor/document/page_painting.dart';
import '../pdf/pdf_renderer.dart';
import 'pdf_export.dart';

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

  /// Resolution of PDF-page backgrounds embedded in exported PDFs.
  static const double backgroundDpi = 150;

  /// A PDF of [pages] (vector ink and templates). [onProgress] hears how
  /// many pages are prepared, then written. Without [backgrounds],
  /// imported PDF pages are left out.
  Future<Uint8List> pdf(
    List<NotebookPage> pages, {
    String? title,
    ExportProgress? onProgress,
    bool backgrounds = true,
  }) async {
    final export = <ExportPage>[];
    try {
      for (final page in pages) {
        onProgress?.call(ExportStage.preparing, export.length, pages.length);
        final background = backgrounds
            ? await _background(page, page.width / 96 * backgroundDpi)
            : null;
        export.add(
          ExportPage(
            page,
            _copier.loadAll(page.id),
            elements: _copier.loadAllElements(page.id),
            background: background,
          ),
        );
      }
      return await PdfExporter.build(
        export,
        title: title,
        onPage: (done) => onProgress?.call(ExportStage.writing, done, export.length),
        readBlob: _readBlob,
      );
    } finally {
      for (final e in export) {
        e.background?.dispose();
      }
    }
  }

  /// A PNG of [page] at [scale] pixels per page unit (2 ≈ 192 dpi);
  /// without [backgrounds], an imported PDF page is left out.
  Future<Uint8List> png(NotebookPage page, {double scale = 2, bool backgrounds = true}) async {
    final background = backgrounds ? await _background(page, page.width * scale) : null;
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
    if (bg == null || !await services.sync.fetchBlob(bg.blob)) return null;
    return _renderer.render(bg.blob, bg.pageIndex, pixelWidth.round());
  }

  Future<void> dispose() => _renderer.dispose();
}
