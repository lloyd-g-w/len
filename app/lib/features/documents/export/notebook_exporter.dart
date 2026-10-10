import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../app_services.dart';
import '../../../data/surface_copier.dart';
import '../../../domain/notebook_page.dart';
import '../../editor/document/page_painting.dart';
import '../pdf/pdf_renderer.dart';
import 'pdf_export.dart';

/// Produces PDF and PNG files from notebook pages.
class NotebookExporter {
  NotebookExporter(this.services, {PdfRenderer? renderer})
    : _renderer = renderer ?? PdfRenderer(),
      _copier = SurfaceCopier(services.strokes);

  final AppServices services;
  final PdfRenderer _renderer;
  final SurfaceCopier _copier;

  /// Resolution of PDF-page backgrounds embedded in exported PDFs.
  static const double backgroundDpi = 150;

  /// A PDF of [pages] (vector ink and templates).
  Future<Uint8List> pdf(List<NotebookPage> pages, {String? title}) async {
    final export = <ExportPage>[];
    try {
      for (final page in pages) {
        final background = await _background(page, page.width / 96 * backgroundDpi);
        export.add(ExportPage(page, _copier.loadAll(page.id), background: background));
      }
      return await PdfExporter.build(export, title: title);
    } finally {
      for (final e in export) {
        e.background?.dispose();
      }
    }
  }

  /// A PNG of [page] at [scale] pixels per page unit (2 ≈ 192 dpi).
  Future<Uint8List> png(NotebookPage page, {double scale = 2}) async {
    final background = await _background(page, page.width * scale);
    final image = await renderPageImage(
      page,
      strokes: _copier.loadAll(page.id),
      scale: scale,
      background: background,
    );
    background?.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<ui.Image?> _background(NotebookPage page, double pixelWidth) async {
    final bg = page.background;
    if (bg == null || !await services.sync.fetchBlob(bg.blob)) return null;
    return _renderer.render(
      bg.blob,
      services.blobs.fileOf(bg.blob).path,
      bg.pageIndex,
      pixelWidth.round(),
    );
  }

  Future<void> dispose() => _renderer.dispose();
}
