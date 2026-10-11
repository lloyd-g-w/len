import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';

import '../../../domain/surface_element.dart';
import '../../../domain/text/text_data.dart';
import '../../../ink/elements/list_marker.dart';
import '../../../ink/elements/text_layout.dart';

/// Loads a bundled font file (an asset path, see [TextFont.asset]).
typedef FontAssetLoader = Future<ByteData> Function(String asset);

/// Writes text boxes into a PDF as real, selectable text in the embedded
/// (subsetted) bundled fonts.
///
/// Glyph positions come from the app's own layout ([TextLayout]): every
/// word is placed where the canvas draws it, so wrapping, alignment, mixed
/// sizes and list markers match the screen; only the spacing *inside* a
/// word comes from the font's advances (no kerning). Highlights,
/// underlines, strikethroughs, bullets and checkboxes are vectors. A box
/// with characters the bundled fonts lack (e.g. CJK, emoji, drawn on screen
/// with system fallback fonts) is left to the caller ([draw] returns
/// false), which embeds it as an image instead.
class PdfTextWriter {
  PdfTextWriter(this.doc, {FontAssetLoader? load}) : _load = load ?? rootBundle.load;

  final PdfDocument doc;
  final FontAssetLoader _load;
  final Map<String, Future<PdfTtfFont>> _fonts = {};

  /// Slant of synthetic italics (fonts without an italic face).
  static const double _slant = 0.2;

  Future<PdfTtfFont> _font(TextFont font, {required bool bold, required bool italic}) {
    final asset = font.asset(bold: bold, italic: italic);
    return _fonts[asset] ??= _load(asset).then((bytes) => PdfTtfFont(doc, bytes));
  }

  /// Draws text box [element]; [toPdf] maps world units to PDF points
  /// ([k] points per unit, PDF y up). False if it cannot be written as
  /// text (see the class doc); nothing was drawn then.
  Future<bool> draw(
    PdfGraphics g,
    SurfaceElement element, {
    required double pageHeight,
    required double k,
  }) async {
    final data = TextData.fromJson(element.data);
    final layout = TextLayout.layout(data, element.rect.width);
    try {
      final runs = await _runs(data, layout);
      if (runs == null) return false;
      g
        ..saveContext()
        ..setTransform(_boxToPdf(element, pageHeight, k));
      for (final r in runs) {
        _highlight(g, r);
      }
      for (final r in runs) {
        _text(g, r);
      }
      for (final r in runs) {
        _decorations(g, r);
      }
      await _markers(g, layout);
      g.restoreContext();
      return true;
    } finally {
      layout.dispose();
    }
  }

  /// Box coordinates (top left = 0, 0, y down, world units) → PDF points.
  static Matrix4 _boxToPdf(SurfaceElement e, double pageHeight, double k) {
    final c = e.rect.center;
    return Matrix4.identity()
      ..translateByDouble(0, pageHeight * k, 0, 1)
      ..scaleByDouble(k, -k, 1, 1)
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..rotateZ(e.rotation)
      ..translateByDouble(e.rect.left - c.dx, e.rect.top - c.dy, 0, 1);
  }

  /// The words of [data] with their fonts and laid-out positions; null if
  /// a character is missing from its font.
  Future<List<_Run>?> _runs(TextData data, TextBoxLayout layout) async {
    final painter = layout.painter;
    final lines = painter.computeLineMetrics();
    final offsets = MarkerOffsets(data);
    final chars = data.charStyles();
    final paras = data.paras;
    final text = data.text;
    final runs = <_Run>[];
    var lineStart = 0;
    for (var line = 0; line < paras.length; line++) {
      final nl = text.indexOf('\n', lineStart);
      final end = nl < 0 ? text.length : nl;
      final para = paras[line];
      var i = lineStart;
      while (i < end) {
        var j = i + 1;
        while (j < end && chars[j] == chars[i]) {
          j++;
        }
        final span = chars[i];
        final style = TextLayout.styleFor(data, span, para);
        final font = span.font ?? data.font;
        final bold = span.bold || para.heading > 0;
        final pdfFont = await _font(font, bold: bold, italic: span.italic);
        final glyphs = pdfFont.font.charToGlyphIndexMap;
        if (text.substring(i, j).runes.any((r) => !glyphs.containsKey(r) && r > 0x20)) {
          return null;
        }
        final run = _Run(
          style: style,
          font: pdfFont,
          slant: span.italic && !font.hasItalic,
          boxes: _boxes(painter, offsets, i, j),
        );
        // Each word separately, at its laid-out position.
        for (final m in RegExp(r'\S+').allMatches(text.substring(i, j))) {
          _place(run, painter, lines, offsets, text, i + m.start, i + m.end);
        }
        runs.add(run);
        i = j;
      }
      lineStart = end + 1;
    }
    return runs;
  }

  static List<Rect> _boxes(TextPainter p, MarkerOffsets o, int start, int end) => [
    for (final b in p.getBoxesForSelection(
      TextSelection(baseOffset: o.toDisplay(start), extentOffset: o.toDisplay(start) + end - start),
      boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
    ))
      b.toRect(),
  ];

  /// Adds the word [start, end) to [run]: whole, or character by character
  /// when the layout broke it across lines.
  static void _place(
    _Run run,
    TextPainter p,
    List<ui.LineMetrics> lines,
    MarkerOffsets o,
    String text,
    int start,
    int end,
  ) {
    final boxes = _boxes(p, o, start, end);
    if (boxes.isEmpty) return;
    if (boxes.length == 1) {
      run.words.add((
        text.substring(start, end),
        boxes.single.left,
        _baseline(lines, boxes.single),
      ));
      return;
    }
    var i = start;
    while (i < end) {
      final n = i + 1 < end && _isLead(text.codeUnitAt(i)) ? 2 : 1;
      final b = _boxes(p, o, i, i + n);
      if (b.isNotEmpty) {
        run.words.add((text.substring(i, i + n), b.first.left, _baseline(lines, b.first)));
      }
      i += n;
    }
  }

  static bool _isLead(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  /// The baseline (from the top) of the line [box] is on.
  static double _baseline(List<ui.LineMetrics> lines, Rect box) {
    final y = box.center.dy;
    var top = 0.0;
    for (final l in lines) {
      if (y < top + l.height) return l.baseline;
      top += l.height;
    }
    return lines.isEmpty ? box.bottom : lines.last.baseline;
  }

  static void _fill(PdfGraphics g, Color c) {
    g
      ..setFillColor(PdfColor.fromInt(c.toARGB32() | 0xFF000000))
      ..setGraphicState(PdfGraphicState(fillOpacity: c.a));
  }

  void _highlight(PdfGraphics g, _Run r) {
    final paint = r.style.background;
    if (paint == null) return;
    _fill(g, paint.color);
    for (final b in r.boxes) {
      g.drawRect(b.left, b.top, b.width, b.height);
    }
    g.fillPath();
  }

  void _text(PdfGraphics g, _Run r) {
    if (r.words.isEmpty) return;
    _fill(g, r.style.color!);
    final size = r.style.fontSize!;
    for (final (word, x, baseline) in r.words) {
      final glyph = Matrix4.identity()
        ..translateByDouble(x, baseline, 0, 1)
        ..scaleByDouble(1, -1, 1, 1);
      if (r.slant) glyph.setEntry(0, 1, _slant);
      g
        ..saveContext()
        ..setTransform(glyph)
        ..drawString(r.font, size, word, 0, 0)
        ..restoreContext();
    }
  }

  void _decorations(PdfGraphics g, _Run r) {
    final deco = r.style.decoration;
    if (deco == null || deco == TextDecoration.none || r.words.isEmpty) return;
    final size = r.style.fontSize!;
    final thickness = math.max(size * 0.05, 0.5);
    _fill(g, r.style.decorationColor ?? r.style.color!);
    final baselines = {for (final w in r.words) w.$3};
    for (final b in r.boxes) {
      final baseline = baselines.firstWhere(
        (y) => y > b.top && y <= b.bottom,
        orElse: () => b.bottom - size * 0.25,
      );
      if (deco.contains(TextDecoration.underline)) {
        g.drawRect(b.left, baseline + size * 0.1, b.width, thickness);
      }
      if (deco.contains(TextDecoration.lineThrough)) {
        g.drawRect(b.left, baseline - size * 0.3, b.width, thickness);
      }
    }
    g.fillPath();
  }

  Future<void> _markers(PdfGraphics g, TextBoxLayout layout) async {
    final boxes = layout.markerBoxes;
    for (var i = 0; i < layout.markers.length && i < boxes.length; i++) {
      final m = layout.markers[i];
      if (m.para.list == ListKind.number) {
        await _number(g, m, boxes[i]);
      } else {
        _shapes(g, m, m.shapes(boxes[i]));
      }
    }
  }

  Future<void> _number(PdfGraphics g, ListMarker m, Rect box) async {
    final label = m.label;
    final p = TextBoxLayout.numberPainter(m, label);
    final origin = TextBoxLayout.numberOrigin(m, p, m.column(box));
    final baseline = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    p.dispose();
    final font = await _font(m.font, bold: false, italic: false);
    _fill(g, Color(m.color));
    g
      ..saveContext()
      ..setTransform(
        Matrix4.identity()
          ..translateByDouble(origin.dx, origin.dy + baseline, 0, 1)
          ..scaleByDouble(1, -1, 1, 1),
      )
      ..drawString(font, m.fontSize, label, 0, 0)
      ..restoreContext();
  }

  void _shapes(PdfGraphics g, ListMarker m, List<MarkerShape> shapes) {
    final ink = PdfColor.fromInt(m.color | 0xFF000000);
    g
      ..setFillColor(ink)
      ..setStrokeColor(ink)
      ..setGraphicState(
        PdfGraphicState(fillOpacity: Color(m.color).a, strokeOpacity: Color(m.color).a),
      );
    for (final s in shapes) {
      final r = s.rect;
      switch (s.kind) {
        case MarkerShapeKind.disc:
          g
            ..drawEllipse(r.center.dx, r.center.dy, r.width / 2, r.height / 2)
            ..fillPath();
        case MarkerShapeKind.ring:
          g
            ..setLineWidth(s.stroke)
            ..drawEllipse(
              r.center.dx,
              r.center.dy,
              (r.width - s.stroke) / 2,
              (r.height - s.stroke) / 2,
            )
            ..strokePath();
        case MarkerShapeKind.square:
          g
            ..drawRect(r.left, r.top, r.width, r.height)
            ..fillPath();
        case MarkerShapeKind.box:
          final d = r.deflate(s.stroke / 2);
          g
            ..setLineWidth(s.stroke)
            ..drawRRect(d.left, d.top, d.width, d.height, s.radius, s.radius)
            ..strokePath();
        case MarkerShapeKind.filledBox:
          g
            ..drawRRect(r.left, r.top, r.width, r.height, s.radius, s.radius)
            ..fillPath();
        case MarkerShapeKind.tick:
          g
            ..saveContext()
            ..setStrokeColor(PdfColors.white)
            ..setLineWidth(s.stroke)
            ..setLineCap(PdfLineCap.round)
            ..setLineJoin(PdfLineJoin.round)
            ..moveTo(s.points.first.dx, s.points.first.dy);
          for (final p in s.points.skip(1)) {
            g.lineTo(p.dx, p.dy);
          }
          g
            ..strokePath()
            ..restoreContext();
      }
    }
  }
}

/// One stretch of equally formatted text on one line.
class _Run {
  _Run({required this.style, required this.font, required this.slant, required this.boxes});

  final TextStyle style;
  final PdfTtfFont font;

  /// Synthetic italic.
  final bool slant;

  /// Laid-out boxes of the whole run (highlight, decorations).
  final List<Rect> boxes;

  /// Words with their left edge and baseline (box coordinates).
  final List<(String, double, double)> words = [];
}
