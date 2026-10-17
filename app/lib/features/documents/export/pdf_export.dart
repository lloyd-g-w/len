import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color, Offset;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:pdf/pdf.dart';

import '../../../domain/notebook_page.dart';
import '../../../domain/paper_pattern.dart';
import '../../../domain/pdf_page_space.dart';
import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/elements/element_renderer.dart';
import '../../../ink/render/outline_sink.dart';
import '../../../ink/render/paper_painter.dart';
import '../../../ink/render/stroke_renderer.dart';
import 'export_page.dart';
import 'export_report.dart';
import 'pdf_bookmarks.dart';
import 'pdf_images.dart';
import 'pdf_links.dart';
import 'pdf_template.dart';
import 'pdf_text.dart';
import 'vector/pdf_page_importer.dart';

export 'export_page.dart';
export 'pdf_bookmarks.dart' show ExportBookmark;

part 'pdf_export_drawing.dart';

/// Writes pages to a PDF with vector ink and vector templates.
///
/// Ink outlines are the exact paths the app renders: their own lines and
/// Bézier curves. Imported PDF pages keep their
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

  /// How far (world units) an exported ink outline may stray from the
  /// screen's: 0.04 units, 10 µm, a tenth of a 300-dpi printer's dot. The
  /// screen fits ten times tighter only so live ink never shimmers when
  /// zoomed in; here it would double the file.
  static const double inkTolerance = 0.04;

  /// How long writing a page's ink runs before letting the event loop
  /// turn.
  static const Duration yieldEvery = Duration(milliseconds: 12);

  /// Path segments of ink one content stream of a page takes before the
  /// ink goes on in another (~100 KB of operators). Streams are compressed
  /// one at a time as the file is saved; in a browser that is pure Dart on
  /// the page's only thread, and a dense page's ink in one stream (4 MB)
  /// held the tab 2.3 s in one task (WebAssembly).
  static const int inkStreamSegments = 3000;

  /// Resolution of rendered elements (text boxes).
  static const double elementDpi = 300;

  /// Largest side (pixels) of one rendered element.
  static const int maxElementPixels = 4096;

  /// The PDF document of [pages]; [onPage] hears how many are written (and
  /// may throw to abandon the export). Image elements are read through
  /// [readBlob]. [onRasterized] hears the index of each page whose PDF
  /// background had to be embedded as an image. [report] collects what was
  /// left out or simplified. [bookmarks] become the document's outline,
  /// shown by readers when it opens.
  static Future<Uint8List> build(
    List<ExportPage> pages, {
    String? title,
    List<ExportBookmark> bookmarks = const [],
    void Function(int done)? onPage,
    Future<Uint8List?> Function(String sha)? readBlob,
    void Function(int index)? onRasterized,
    FontAssetLoader? loadFont,
    ExportReport? report,
  }) async {
    final doc = PdfDocument(pageMode: bookmarks.isEmpty ? PdfPageMode.none : PdfPageMode.outlines);
    PdfInfo(doc, title: title, creator: 'Len', producer: 'Len'); // Registers itself.
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
      if (!await _addPage(writer, pages[i])) {
        onRasterized?.call(i);
        report?.rasterizedPages++;
      }
    }
    report?.missingImages += writer.images.missing;
    PdfLinkWriter.write(doc, pages, writer.written, writer.links);
    writeBookmarks(doc, bookmarks, writer.written);
    // In a browser the save runs on the page's thread: it lets the event
    // loop turn between objects (elsewhere it runs in an isolate).
    return doc.save(enableEventLoopBalancing: kIsWeb);
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

    // A scan, and an image template (My templates: the page's paper), are
    // embedded at their stored resolution.
    if (export.image case final blob?) {
      await images.drawPage(g, blob, format.width, format.height);
    }
    if (page.paper.image case final blob?) {
      await images.drawPage(g, blob, format.width, format.height);
    }
    await _drawPattern(pen, page, templates, worldOrigin: export.worldOrigin);
    final elements = [...export.elements]..sort(SurfaceElement.paintOrder);
    Future<void> drawElements(bool belowInk) async {
      for (final element in elements.where((e) => e.belowInk == belowInk)) {
        if (element.knownType == ElementType.image) {
          await images.draw(pen.g, element, toPdf: pen.map, k: k);
        } else if (element.knownType == ElementType.text &&
            await writer.text.draw(pen.g, element, pageHeight: page.height, k: k)) {
          // Written as text.
        } else {
          await _drawElement(doc, pen, element);
        }
      }
    }

    await drawElements(true);
    // Highlighter beneath pen ink, as on screen (see ContentPainter).
    final slice = Stopwatch()..start();
    pen.segments = 0;
    for (final stroke in [...export.strokes]..sort(Stroke.drawOrder)) {
      _drawStroke(pen, stroke);
      // Each stroke is a whole q … Q: the next one may start a new stream.
      if (pen.segments > inkStreamSegments) {
        pen
          ..g = pdfPage.getGraphics()
          ..segments = 0;
      }
      // A dense page takes seconds in a browser, all on its one thread:
      // the tab (progress, Cancel) keeps responding.
      if (slice.elapsed > yieldEvery) {
        await Future<void>.delayed(Duration.zero);
        slice.reset();
      }
    }
    await drawElements(false);
    return vector;
  }
}
