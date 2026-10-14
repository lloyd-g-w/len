part of 'pdf_export.dart';

/// Draws [background] over the page [format]: as vectors if its source
/// page can be copied, else as an image; returns whether it was vectors.
Future<bool> _drawBackground(
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
Future<void> _drawElement(PdfDocument doc, _Pen pen, SurfaceElement element) async {
  // Not drawn by this version; links become annotations.
  if (element.knownType == null || element.knownType == ElementType.link) return;
  final bounds = element.bounds;
  if (bounds.isEmpty || !bounds.isFinite) return;
  final scale = math.min(
    PdfExporter.elementDpi / 96,
    PdfExporter.maxElementPixels / math.max(bounds.width, bounds.height),
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
      width / scale * PdfExporter.pointsPerUnit,
      height / scale * PdfExporter.pointsPerUnit,
    );
  } finally {
    image.dispose();
  }
}

/// Drops the alpha channel (backgrounds are opaque).
Uint8List _rgb(Uint8List rgba) {
  final rgb = Uint8List(rgba.length ~/ 4 * 3);
  for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
    rgb[j] = rgba[i];
    rgb[j + 1] = rgba[i + 1];
    rgb[j + 2] = rgba[i + 2];
  }
  return rgb;
}

Future<void> _drawPattern(
  _Pen pen,
  NotebookPage page,
  PdfTemplateWriter templates, {
  Offset? worldOrigin,
}) {
  final rect = Offset.zero & page.size;
  final origin = worldOrigin;
  return templates.draw(
    pen.g,
    origin == null
        ? PaperPattern.of(page.paper, rect, page: rect)
        : PaperPattern.of(page.paper, rect.shift(origin)),
    page.paperColor,
    look: page.paper.look,
    margin: const PaperColors().margin,
    map: origin == null ? pen.map : (p) => pen.map(p - origin),
    k: PdfExporter.pointsPerUnit,
  );
}

void _drawStroke(_Pen pen, Stroke stroke) {
  _drawFill(pen, stroke);
  // Same colour and opacity as on screen.
  final base = Color(stroke.color);
  final color = base.withValues(alpha: base.a * stroke.style.opacity);
  final g = pen.g
    ..saveContext()
    ..setGraphicState(PdfGraphicState(fillOpacity: color.a))
    ..setFillColor(PdfColor.fromInt(color.toARGB32() | 0xFF000000));
  for (final metric in StrokeRenderer.pathOf(stroke).computeMetrics()) {
    final n = math.max(3, (metric.length / PdfExporter.flattenStep).ceil());
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

/// A filled shape's fill ([Stroke.fill]), beneath its outline: the
/// polygon of its points, as on screen.
void _drawFill(_Pen pen, Stroke stroke) {
  final fill = stroke.fill;
  if (fill == null) return;
  final color = Color(fill);
  final g = pen.g
    ..saveContext()
    ..setGraphicState(PdfGraphicState(fillOpacity: color.a))
    ..setFillColor(PdfColor.fromInt(fill | 0xFF000000));
  final points = stroke.points;
  pen.moveTo(points.first.offset);
  for (var i = 1; i < points.length; i++) {
    pen.lineTo(points[i].offset);
  }
  g
    ..closePath()
    ..fillPath()
    ..restoreContext();
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
