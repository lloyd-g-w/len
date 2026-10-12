import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color, Offset;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:pdf/pdf.dart';

import '../../../domain/notebook_page.dart';
import '../../../domain/paper_pattern.dart';
import '../../../domain/pdf_page_space.dart';
import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/elements/element_renderer.dart';
import '../../../ink/render/paper_painter.dart';
import '../../../ink/render/stroke_renderer.dart';
import 'pdf_images.dart';
import 'pdf_links.dart';
import 'pdf_template.dart';
import 'pdf_text.dart';
import 'vector/pdf_page_importer.dart';
import 'vector/pdf_source_reader.dart';

/// A page to export with its ink, elements and (pre-rendered) background.
class ExportPage {
  const ExportPage(this.page, this.strokes, {this.elements = const [], this.background});

  final NotebookPage page;
  final List<Stroke> strokes;

  /// Text boxes, images and other elements on the page (each beneath or
  /// above the ink, see [SurfaceElement.belowInk]).
  final List<SurfaceElement> elements;

  /// The imported PDF page behind everything, if any.
  final ExportBackground? background;
}

/// An imported PDF page to export behind a page's content: copied from
/// [source] as vectors when possible, else embedded as the image [raster]
/// renders.
class ExportBackground {
  const ExportBackground({required this.pageIndex, required this.raster, this.source, this.links});

  /// The parsed source PDF; null when it can only be rasterised.
  final PdfSourceReader? source;

  /// The page of [source] (zero-based).
  final int pageIndex;

  /// Renders the page as an opaque image (the caller's to dispose).
  final Future<ui.Image?> Function() raster;

  /// Reads the page's links (normalised to the page as shown) when it is
  /// embedded as an image; a copied page brings its own.
  final Future<List<PdfLinkArea>> Function()? links;
}

/// Writes pages to a PDF with vector ink and vector templates.
///
/// Ink outlines are the exact paths the app renders, flattened into
/// polygons finer than the eye can see. Imported PDF pages keep their
/// original content: each is copied from its source PDF as a Form XObject
/// (text stays text, vectors stay vectors; [PdfPageImporter]), and only a
/// page that cannot be copied is embedded as an image. Text boxes are real,
/// selectable text in the embedded bundled fonts, placed word by word where
/// the app's layout puts them ([PdfTextWriter]); a box with characters the
/// bundled fonts lack is embedded as a transparent image rendered at
/// [elementDpi] by the app's own text renderer instead. Image
/// elements are embedded at their stored resolution ([PdfImageWriter]),
/// read through `readBlob`.
abstract final class PdfExporter {
  /// PDF points (1/72 in) per world unit (1/96 in).
  static const double pointsPerUnit = 72 / 96;

  /// Maximum distance between polygon points along a curve, in world units.
  static const double flattenStep = 0.75;

  /// Resolution of rendered elements (text boxes).
  static const double elementDpi = 300;

  /// Largest side (pixels) of one rendered element.
  static const int maxElementPixels = 4096;

  /// The PDF document of [pages]; [onPage] hears how many are written (and
  /// may throw to abandon the export). Image elements are read through
  /// [readBlob]. [onRasterized] hears the index of each page whose PDF
  /// background had to be embedded as an image.
  static Future<Uint8List> build(
    List<ExportPage> pages, {
    String? title,
    void Function(int done)? onPage,
    Future<Uint8List?> Function(String sha)? readBlob,
    void Function(int index)? onRasterized,
    FontAssetLoader? loadFont,
  }) async {
    final doc = PdfDocument();
    PdfInfo(doc, title: title, creator: 'Len'); // Registers itself.
    final text = PdfTextWriter(doc, load: loadFont);
    final writer = _Writer(
      doc,
      PdfImageWriter(doc, readBlob ?? (_) async => null),
      PdfPageImporter(doc),
      PdfTemplateWriter(text),
      text,
    );
    for (var i = 0; i < pages.length; i++) {
      onPage?.call(i);
      if (!await _addPage(writer, pages[i])) onRasterized?.call(i);
    }
    PdfLinkWriter.write(doc, pages, writer.written, writer.links);
    return doc.save();
  }

  /// Writes [export]; false if its PDF background had to be rasterised.
  static Future<bool> _addPage(_Writer writer, ExportPage export) async {
    final _Writer(:doc, :images, :templates) = writer;
    var vector = true;
    final page = export.page;
    const k = pointsPerUnit;
    final format = PdfPageFormat(page.width * k, page.height * k);
    final pdfPage = PdfPage(doc, pageFormat: format);
    writer.written.add(pdfPage);
    writer.links.add(const []);
    final g = pdfPage.getGraphics();
    final pen = _Pen(g, page.height);

    g
      ..setFillColor(PdfColor.fromInt(page.paperColor.paper.toARGB32()))
      ..drawRect(0, 0, format.width, format.height)
      ..fillPath();

    final background = export.background;
    if (background != null) {
      vector = await _drawBackground(writer, g, background, format);
    }

    // An image template (My templates) is the page's paper, embedded at
    // its stored resolution.
    if (page.paper.image case final blob?) {
      await images.drawPage(g, blob, format.width, format.height);
    }
    await _drawPattern(pen, page, templates);
    final elements = [...export.elements]..sort(SurfaceElement.paintOrder);
    Future<void> drawElements(bool belowInk) async {
      for (final element in elements.where((e) => e.belowInk == belowInk)) {
        if (element.knownType == ElementType.image) {
          await images.draw(g, element, toPdf: pen.map, k: k);
        } else if (element.knownType == ElementType.text &&
            await writer.text.draw(g, element, pageHeight: page.height, k: k)) {
          // Written as text.
        } else {
          await _drawElement(doc, pen, element);
        }
      }
    }

    await drawElements(true);
    // Highlighter beneath pen ink, as on screen (see ContentPainter).
    for (final stroke in [...export.strokes]..sort(Stroke.drawOrder)) {
      _drawStroke(pen, stroke);
    }
    await drawElements(false);
    return vector;
  }

  /// Draws [background] over the page [format]: as vectors if its source
  /// page can be copied, else as an image; returns whether it was vectors.
  static Future<bool> _drawBackground(
    _Writer writer,
    PdfGraphics g,
    ExportBackground background,
    PdfPageFormat format,
  ) async {
    final source = background.source;
    if (source != null) {
      try {
        final page = writer.importer.importPage(source, background.pageIndex);
        page.draw(g, format.width, format.height);
        writer.links.last = page.links;
        return true;
      } catch (e) {
        // Unsupported or malformed page content: fall back to an image.
        debugPrint('PDF page ${background.pageIndex} is exported as an image: $e');
      }
    }
    try {
      writer.links.last = await background.links?.call() ?? const [];
    } catch (e) {
      debugPrint('Links of PDF page ${background.pageIndex} are left out: $e');
    }
    final image = await background.raster();
    if (image == null) return false;
    try {
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) return false;
      final embedded = PdfImage(
        writer.doc,
        image: _rgb(rgba.buffer.asUint8List()),
        width: image.width,
        height: image.height,
        alpha: false,
      );
      g.drawImage(embedded, 0, 0, format.width, format.height);
    } finally {
      image.dispose();
    }
    return false;
  }

  /// Embeds [element] as a transparent image over its (rotated) bounds.
  static Future<void> _drawElement(PdfDocument doc, _Pen pen, SurfaceElement element) async {
    // Not drawn by this version; links become annotations.
    if (element.knownType == null || element.knownType == ElementType.link) return;
    final bounds = element.bounds;
    if (bounds.isEmpty || !bounds.isFinite) return;
    final scale = math.min(
      elementDpi / 96,
      maxElementPixels / math.max(bounds.width, bounds.height),
    );
    final width = (bounds.width * scale).ceil(), height = (bounds.height * scale).ceil();
    if (width <= 0 || height <= 0) return;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..scale(scale)
      ..translate(-bounds.left, -bounds.top);
    ElementRenderer.draw(canvas, element);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    try {
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (rgba == null) return;
      final pdfImage = PdfImage(
        doc,
        image: rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
        width: width,
        height: height,
      );
      final bottomLeft = pen.map(bounds.bottomLeft);
      pen.g.drawImage(
        pdfImage,
        bottomLeft.dx,
        bottomLeft.dy,
        width / scale * pointsPerUnit,
        height / scale * pointsPerUnit,
      );
    } finally {
      image.dispose();
    }
  }

  /// Drops the alpha channel (backgrounds are opaque).
  static Uint8List _rgb(Uint8List rgba) {
    final rgb = Uint8List(rgba.length ~/ 4 * 3);
    for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
      rgb[j] = rgba[i];
      rgb[j + 1] = rgba[i + 1];
      rgb[j + 2] = rgba[i + 2];
    }
    return rgb;
  }

  static Future<void> _drawPattern(_Pen pen, NotebookPage page, PdfTemplateWriter templates) {
    final rect = Offset.zero & page.size;
    return templates.draw(
      pen.g,
      PaperPattern.of(page.paper, rect, page: rect),
      page.paperColor,
      margin: const PaperColors().margin,
      map: pen.map,
      k: pointsPerUnit,
    );
  }

  static void _drawStroke(_Pen pen, Stroke stroke) {
    // Same colour and opacity as on screen (textured pens become flat ink).
    final base = Color(stroke.color);
    final color = base.withValues(alpha: base.a * stroke.style.opacity);
    final g = pen.g
      ..saveContext()
      ..setGraphicState(PdfGraphicState(fillOpacity: color.a))
      ..setFillColor(PdfColor.fromInt(color.toARGB32() | 0xFF000000));
    for (final metric in StrokeRenderer.pathOf(stroke).computeMetrics()) {
      final n = math.max(3, (metric.length / flattenStep).ceil());
      for (var i = 0; i < n; i++) {
        final t = metric.getTangentForOffset(metric.length * i / n);
        if (t == null) continue;
        i == 0 ? pen.moveTo(t.position) : pen.lineTo(t.position);
      }
      g.closePath();
    }
    g
      ..fillPath()
      ..restoreContext();
  }
}

/// What one export writes with.
class _Writer {
  _Writer(this.doc, this.images, this.importer, this.templates, this.text);

  final PdfDocument doc;
  final PdfImageWriter images;
  final PdfPageImporter importer;
  final PdfTemplateWriter templates;
  final PdfTextWriter text;

  /// The PDF pages written so far, in order.
  final List<PdfPage> written = [];

  /// The links of each written page's PDF background.
  final List<List<PdfLinkArea>> links = [];
}

/// Maps world coordinates (y down) to PDF points (y up).
class _Pen {
  _Pen(this.g, this.pageHeight);

  final PdfGraphics g;
  final double pageHeight;

  Offset map(Offset p) =>
      Offset(p.dx * PdfExporter.pointsPerUnit, (pageHeight - p.dy) * PdfExporter.pointsPerUnit);

  void moveTo(Offset p) {
    final m = map(p);
    g.moveTo(m.dx, m.dy);
  }

  void lineTo(Offset p) {
    final m = map(p);
    g.lineTo(m.dx, m.dy);
  }
}
