import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../app_services.dart';
import '../../../data/surface_copier.dart';
import '../../../domain/image_data.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/paper.dart';
import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/surface_model.dart';
import '../../editor/document/page_painting.dart';
import '../pdf/pdf_renderer.dart';
import 'export_report.dart';
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
  /// [pages]) of each PDF page that had to be embedded as an image;
  /// [report] collects what was left out or simplified.
  Future<Uint8List> pdf(
    List<NotebookPage> pages, {
    String? title,
    ExportProgress? onProgress,
    bool backgrounds = true,
    void Function(int index)? onRasterized,
    ExportReport? report,
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
          background: backgrounds ? await _exportBackground(page, sources, report) : null,
          image: backgrounds ? await _imageBackground(page, report) : null,
        ),
      );
    }
    return PdfExporter.build(
      export,
      title: title,
      onPage: (done) => onProgress?.call(ExportStage.writing, done, export.length),
      readBlob: _readBlob,
      onRasterized: onRasterized,
      report: report,
    );
  }

  Future<ExportBackground?> _exportBackground(
    NotebookPage page,
    PdfPageSources sources,
    ExportReport? report,
  ) async {
    final bg = page.pdf;
    if (bg == null) return null;
    if (!await services.sync.fetchBlob(bg.blob)) {
      report?.missingBackgrounds++;
      return null;
    }
    return ExportBackground(
      source: await sources.sourceOf(bg.blob),
      pageIndex: bg.pageIndex,
      raster: () => _background(page, page.width / 96 * backgroundDpi),
      links: () => _renderer.links(bg.blob, bg.pageIndex),
    );
  }

  /// The blob of [page]'s image background (a scan), if it can be had.
  Future<String?> _imageBackground(NotebookPage page, ExportReport? report) async {
    final bg = page.background;
    if (bg == null || bg.isPdf) return null;
    if (await services.sync.fetchBlob(bg.blob)) return bg.blob;
    report?.missingBackgrounds++;
    return null;
  }

  /// A PNG of [page] at [scale] pixels per page unit (2 ≈ 192 dpi);
  /// without [backgrounds], an imported PDF page or scan is left out (an image
  /// template stays: it is the page's paper). [report] collects what was
  /// left out.
  Future<Uint8List> png(
    NotebookPage page, {
    double scale = 2,
    bool backgrounds = true,
    ExportReport? report,
  }) async {
    SurfaceModel.flushAll(); // Ink drawn a moment ago.
    final paperOnly = page.background == null && page.paper.image != null;
    final background = backgrounds || paperOnly
        ? await _background(page, page.width * scale)
        : null;
    if (background == null && paperOnly) report?.missingImages++;
    if (background == null && backgrounds && page.background != null) {
      report?.missingBackgrounds++;
    }
    final elements = _copier.loadAllElements(page.id);
    await _loadImages(elements, scale, report);
    if (!paperOnly) await _loadTemplate(page.paper, page.width * scale, report);
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

  /// Room left around a canvas's drawing when it is exported (world units:
  /// half an inch).
  static const double canvasMargin = 48;

  /// Longest side, in pixels, of an exported canvas PNG: a large drawing
  /// is exported at a lower resolution rather than as an unopenable file.
  static const int maxCanvasPixels = 8192;

  /// Infinite canvas [notebook]'s drawing as one page: everything on it
  /// plus [canvasMargin], on its paper (or white paper without
  /// [template]), with the pattern aligned as on screen. Null if the
  /// canvas is empty.
  ExportPage? canvasPage(Notebook notebook, {bool template = true}) {
    SurfaceModel.flushAll(); // Ink drawn a moment ago.
    final bounds = services.strokes.contentBounds(notebook.id);
    if (bounds == null || bounds.isEmpty) return null;
    final area = bounds.inflate(canvasMargin);
    final origin = area.topLeft;
    final page = NotebookPage(
      id: notebook.id,
      notebookId: notebook.id,
      sortKey: 0,
      width: area.width,
      height: area.height,
      paper: template ? notebook.paper : Paper.blank,
      paperColor: template ? notebook.paperColor : PaperColor.white,
    );
    return ExportPage(
      page,
      [
        for (final s in _copier.loadAll(notebook.id))
          s.withPoints([
            for (final p in s.points) StrokePoint(p.x - origin.dx, p.y - origin.dy, p.pressure),
          ]),
      ],
      elements: [
        for (final e in _copier.loadAllElements(notebook.id))
          e.copyWith(rect: e.rect.shift(-origin)),
      ],
      worldOrigin: origin,
    );
  }

  /// A one-page PDF of a canvas's drawing ([canvasPage]).
  Future<Uint8List> canvasPdf(ExportPage canvas, {String? title, ExportReport? report}) =>
      PdfExporter.build([canvas], title: title, readBlob: _readBlob, report: report);

  /// A PNG of a canvas's drawing ([canvasPage]) at [scale] pixels per
  /// world unit, or less for a drawing too large for [maxCanvasPixels].
  /// [report] collects images left out.
  Future<Uint8List> canvasPng(ExportPage canvas, {double scale = 2, ExportReport? report}) async {
    final page = canvas.page;
    final fitted = math.min(scale, maxCanvasPixels / math.max(page.width, page.height));
    await _loadImages(canvas.elements, fitted, report);
    final image = await renderPageImage(
      page,
      strokes: canvas.strokes,
      elements: canvas.elements,
      scale: fitted,
      images: services.images,
      worldOrigin: canvas.worldOrigin,
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Decodes the images among [elements] for drawing at [scale] pixels per
  /// unit (painting only uses what is ready), counting those that can't be
  /// had in [report].
  Future<void> _loadImages(
    List<SurfaceElement> elements,
    double scale,
    ExportReport? report,
  ) async {
    for (final e in elements.where((e) => e.knownType == ElementType.image)) {
      final data = ImageData.fromJson(e.data);
      final image = await services.images.load(data, e.rect.width * scale / data.crop.width);
      if (image == null) report?.missingImages++;
    }
  }

  /// Decodes [paper]'s image template, if it has one, for drawing
  /// [pixelWidth] wide (the pattern draws it from the decoded images; over
  /// a scan or a PDF page it is no background).
  Future<void> _loadTemplate(Paper paper, double pixelWidth, ExportReport? report) async {
    final template = paper.image;
    if (template == null) return;
    final image = ImageData(blob: template, width: 0, height: 0);
    if (await services.images.load(image, pixelWidth) == null) report?.missingImages++;
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
    if (!bg.isPdf) {
      final image = ImageData(blob: bg.blob, width: 0, height: 0);
      return (await services.images.load(image, pixelWidth))?.clone();
    }
    return _renderer.render(bg.blob, bg.pageIndex, pixelWidth.round());
  }

  Future<void> dispose() => _renderer.dispose();
}
