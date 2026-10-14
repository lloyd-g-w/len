import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';

import '../../../domain/surface_element.dart';
import '../../../domain/text/text_data.dart';
import '../../../ink/elements/text_layout.dart';

part 'pdf_text_drawing.dart';

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

  /// The embedded face of a bundled [font], loaded once per document
  /// (also used for template labels, see `PdfTemplateWriter`).
  Future<PdfTtfFont> font(TextFont font, {required bool bold, required bool italic}) {
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
        final pdfFont = await this.font(font, bold: bold, italic: span.italic);
        final glyphs = pdfFont.font.charToGlyphIndexMap;
        if (text.substring(i, j).runes.any((r) => !glyphs.containsKey(r) && r > 0x20)) {
          return null;
        }
        final run = _Run(
          style: style,
          font: pdfFont,
          slant: span.italic && !font.hasItalic,
          boxes: _boxes(layout, i, j),
        );
        // Each word separately, at its laid-out position.
        for (final m in RegExp(r'\S+').allMatches(text.substring(i, j))) {
          _place(run, layout, lines, text, i + m.start, i + m.end);
        }
        runs.add(run);
        i = j;
      }
      lineStart = end + 1;
    }
    return runs;
  }

  /// Laid-out boxes of the text [start, end) (model offsets, one line of
  /// the box's text), without the breaks and gaps of hanging indents.
  static List<Rect> _boxes(TextBoxLayout layout, int start, int end) {
    final cuts = [start, ...layout.wraps.where((w) => w > start && w < end), end];
    return [
      for (var k = 0; k + 1 < cuts.length; k++)
        for (final b in layout.painter.getBoxesForSelection(
          TextSelection(
            baseOffset: layout.offsets.toDisplay(cuts[k]),
            extentOffset: layout.offsets.toDisplay(cuts[k]) + cuts[k + 1] - cuts[k],
          ),
          boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
        ))
          b.toRect(),
    ];
  }

  /// Adds the word [start, end) to [run]: whole, or character by character
  /// when the layout broke it across lines.
  static void _place(
    _Run run,
    TextBoxLayout layout,
    List<ui.LineMetrics> lines,
    String text,
    int start,
    int end,
  ) {
    final boxes = _boxes(layout, start, end);
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
      final b = _boxes(layout, i, i + n);
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
