import 'dart:ui' show Color, Offset;

import 'package:pdf/pdf.dart';

import '../../../domain/paper.dart';
import '../../../domain/paper_pattern.dart';

/// Writes a template's pattern into a PDF page as vectors: tints, lines
/// (by weight), dots and printed labels (planner dates and headings in
/// Helvetica). [map] turns world coordinates into PDF points; [k] is PDF
/// points per world unit.
class PdfTemplateWriter {
  PdfTemplateWriter(this.doc);

  final PdfDocument doc;
  late final PdfFont _regular = PdfFont.helvetica(doc);
  late final PdfFont _bold = PdfFont.helveticaBold(doc);

  void draw(
    PdfGraphics g,
    PaperPattern pattern,
    PaperColor color, {
    required Color margin,
    required Offset Function(Offset) map,
    required double k,
  }) {
    for (final f in pattern.fills) {
      final a = map(f.rect.bottomLeft), b = map(f.rect.topRight);
      g
        ..saveContext()
        ..setGraphicState(PdfGraphicState(fillOpacity: color.pattern.a * f.opacity))
        ..setFillColor(_opaque(color.pattern))
        ..drawRect(a.dx, a.dy, b.dx - a.dx, b.dy - a.dy)
        ..fillPath()
        ..restoreContext();
    }
    for (final weight in PatternWeight.values) {
      final lines = pattern.lines.where((l) => l.weight == weight);
      if (lines.isEmpty) continue;
      final c = switch (weight) {
        PatternWeight.margin => margin,
        PatternWeight.heavy => Color.lerp(color.pattern, color.text, 0.22)!,
        _ => color.pattern,
      };
      g
        ..saveContext()
        ..setGraphicState(PdfGraphicState(strokeOpacity: c.a))
        ..setStrokeColor(_opaque(c))
        ..setLineWidth(switch (weight) {
          PatternWeight.fine => 0.3,
          PatternWeight.normal => 0.5,
          PatternWeight.heavy || PatternWeight.margin => 0.9,
        });
      for (final l in lines) {
        final a = map(l.a), b = map(l.b);
        g
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
      }
      g
        ..strokePath()
        ..restoreContext();
    }
    if (pattern.dots.isNotEmpty) {
      g.setFillColor(_opaque(color.pattern));
      for (final d in pattern.dots) {
        final c = map(d);
        g.drawEllipse(c.dx, c.dy, 1.05, 1.05);
      }
      g.fillPath();
    }
    for (final label in pattern.labels) {
      _label(g, label, color, map, k);
    }
  }

  void _label(
    PdfGraphics g,
    PatternLabel label,
    PaperColor color,
    Offset Function(Offset) map,
    double k,
  ) {
    final font = label.bold ? _bold : _regular;
    final text = _latin1(label.text);
    final size = label.size * k;
    final width = font.stringMetrics(text).width * size;
    final box = label.box;
    final left = map(box.topLeft).dx, right = map(box.topRight).dx;
    final x = switch (label.align) {
      LabelAlign.start => left,
      LabelAlign.center => (left + right - width) / 2,
      LabelAlign.end => right - width,
    };
    // Baseline: the cap height centred in the box.
    final y = map(box.centerLeft).dy - size * 0.35;
    final c = label.muted ? color.text.withValues(alpha: 0.62) : color.text;
    g
      ..saveContext()
      ..setGraphicState(PdfGraphicState(fillOpacity: c.a))
      ..setFillColor(_opaque(c))
      ..drawString(font, size, text, x, y)
      ..restoreContext();
  }

  static PdfColor _opaque(Color c) => PdfColor.fromInt(c.toARGB32() | 0xFF000000);

  /// The standard PDF fonts cover Latin-1 (plus a few punctuation marks);
  /// labels only need dashes beyond that.
  static String _latin1(String s) => s.replaceAll('–', '-').replaceAll('…', '...');
}
