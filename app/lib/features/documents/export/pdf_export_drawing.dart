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
  // The outline's own segments, as the screen fills them (UX_AUDIT R22-1:
  // sampled polygons made a written page megabytes).
  StrokeRenderer.emitOutline(
    _PdfOutlineSink(pen),
    stroke.points,
    width: stroke.width,
    style: stroke.style,
    complete: true,
    tolerance: PdfExporter.inkTolerance,
  );
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

  /// Where it writes: the page's current content stream.
  PdfGraphics g;
  final double pageHeight;

  /// Path segments written since this was last reset.
  int segments = 0;

  Offset map(Offset p) =>
      Offset(p.dx * PdfExporter.pointsPerUnit, (pageHeight - p.dy) * PdfExporter.pointsPerUnit);

  void moveTo(Offset p) {
    final m = map(p);
    segments++;
    g.moveTo(m.dx, m.dy);
  }

  void lineTo(Offset p) {
    final m = map(p);
    segments++;
    g.lineTo(m.dx, m.dy);
  }
}

/// Writes a stroke outline's segments as PDF path operators through [pen]:
/// lines and cubic Béziers as they are, arcs as Béziers of at most a
/// quarter turn (off by under 0.03 % of the radius). Coordinates are
/// rounded to 1/[step] point (1/100 pt, 3.5 µm): a third of the digits.
class _PdfOutlineSink implements OutlineSink {
  _PdfOutlineSink(this.pen);

  final _Pen pen;

  static const double step = 100;

  static double _r(double v) => (v * step).roundToDouble() / step;

  /// Where the path is (as written, rounded); null after a close.
  Offset? _at;

  Offset _map(double x, double y) {
    final p = pen.map(Offset(x, y));
    return Offset(_r(p.dx), _r(p.dy));
  }

  @override
  void moveTo(double x, double y) {
    final p = _at = _map(x, y);
    pen.segments++;
    pen.g.moveTo(p.dx, p.dy);
  }

  /// A line, unless it goes nowhere: an arc starts with a line to its
  /// start, mostly where the segment before it ended.
  @override
  void lineTo(double x, double y) {
    final p = _map(x, y);
    if (p == _at) return;
    _at = p;
    pen.segments++;
    pen.g.lineTo(p.dx, p.dy);
  }

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) {
    final a = _map(x1, y1), b = _map(x2, y2), c = _at = _map(x3, y3);
    pen.segments++;
    pen.g.curveTo(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy);
  }

  @override
  void arc(double cx, double cy, double radius, double start, double sweep) {
    Offset at(double angle) => Offset(cx + radius * math.cos(angle), cy + radius * math.sin(angle));
    lineTo(at(start).dx, at(start).dy);
    if (sweep == 0 || radius == 0) return;
    final n = (sweep.abs() / (math.pi / 2)).ceil();
    final turn = sweep / n;
    final k = 4 / 3 * math.tan(turn / 4) * radius;
    for (var i = 0; i < n; i++) {
      final a0 = start + turn * i, a1 = a0 + turn;
      final p0 = at(a0), p3 = at(a1);
      final p1 = p0 + Offset(-math.sin(a0), math.cos(a0)) * k;
      final p2 = p3 - Offset(-math.sin(a1), math.cos(a1)) * k;
      cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);
    }
  }

  @override
  void close() {
    _at = null;
    pen.g.closePath();
  }
}
