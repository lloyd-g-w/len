import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color, Offset;

import 'package:pdf/pdf.dart';

import '../../../domain/notebook_page.dart';
import '../../../domain/paper_pattern.dart';
import '../../../domain/stroke.dart';
import '../../../ink/render/paper_painter.dart';
import '../../../ink/render/stroke_renderer.dart';

/// A page to export with its ink and (pre-rendered) background.
class ExportPage {
  const ExportPage(this.page, this.strokes, {this.background});

  final NotebookPage page;
  final List<Stroke> strokes;

  /// The rendered background (e.g. the imported PDF page), if any.
  final ui.Image? background;
}

/// Writes pages to a PDF with vector ink and vector templates.
///
/// Ink outlines are the exact paths the app renders, flattened into
/// polygons finer than the eye can see; backgrounds of imported PDF pages
/// are embedded as images.
abstract final class PdfExporter {
  /// PDF points (1/72 in) per world unit (1/96 in).
  static const double pointsPerUnit = 72 / 96;

  /// Maximum distance between polygon points along a curve, in world units.
  static const double flattenStep = 0.75;

  static Future<Uint8List> build(List<ExportPage> pages, {String? title}) async {
    final doc = PdfDocument();
    PdfInfo(doc, title: title, creator: 'Len'); // Registers itself.
    for (final p in pages) {
      await _addPage(doc, p);
    }
    return doc.save();
  }

  static Future<void> _addPage(PdfDocument doc, ExportPage export) async {
    final page = export.page;
    const k = pointsPerUnit;
    final format = PdfPageFormat(page.width * k, page.height * k);
    final g = PdfPage(doc, pageFormat: format).getGraphics();
    final pen = _Pen(g, page.height);

    g
      ..setFillColor(PdfColor.fromInt(page.paperColor.paper.toARGB32()))
      ..drawRect(0, 0, format.width, format.height)
      ..fillPath();

    final background = export.background;
    if (background != null) {
      final rgba = await background.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba != null) {
        final image = PdfImage(
          doc,
          image: _rgb(rgba.buffer.asUint8List()),
          width: background.width,
          height: background.height,
          alpha: false,
        );
        g.drawImage(image, 0, 0, format.width, format.height);
      }
    }

    _drawPattern(pen, page);
    for (final stroke in [...export.strokes]..sort(Stroke.paintOrder)) {
      _drawStroke(pen, stroke);
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

  static void _drawPattern(_Pen pen, NotebookPage page) {
    final rect = Offset.zero & page.size;
    final pattern = PaperPattern.of(page.paper, rect, page: rect);
    final g = pen.g;
    for (final weight in PatternWeight.values) {
      final lines = pattern.lines.where((l) => l.weight == weight);
      if (lines.isEmpty) continue;
      final color = weight == PatternWeight.margin
          ? const PaperColors().margin
          : page.paperColor.pattern;
      g
        ..saveContext()
        ..setGraphicState(PdfGraphicState(strokeOpacity: color.a))
        ..setStrokeColor(PdfColor.fromInt(color.toARGB32() | 0xFF000000))
        ..setLineWidth(weight == PatternWeight.normal ? 0.5 : 0.9);
      for (final l in lines) {
        pen.moveTo(l.a);
        pen.lineTo(l.b);
      }
      g
        ..strokePath()
        ..restoreContext();
    }
    if (pattern.dots.isNotEmpty) {
      g.setFillColor(PdfColor.fromInt(page.paperColor.pattern.toARGB32()));
      for (final d in pattern.dots) {
        final c = pen.map(d);
        g.drawEllipse(c.dx, c.dy, 1.05, 1.05);
      }
      g.fillPath();
    }
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
