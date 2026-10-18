import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';

import '../../../domain/surface_element.dart';
import '../../../domain/text/font_file.dart';
import '../../../domain/text/text_data.dart';
import '../../../ink/elements/shown_text_layout.dart';
import '../../../ink/elements/text_layout.dart';
import '../../../ink/fonts/text_fonts.dart';
import 'arabic_forms.dart';

part 'pdf_glyph_placer.dart';
part 'pdf_text_drawing.dart';

/// Loads a bundled font file (an asset path, see [TextFont.asset]).
typedef FontAssetLoader = Future<ByteData> Function(String asset);

/// The file of a user font (null: not to be had).
typedef UserFontLoader = Future<Uint8List?> Function(TextFont font);

/// Writes text boxes into a PDF as real, selectable text in the embedded
/// (subsetted) bundled fonts, and the user's fonts that have TrueType
/// outlines (CFF ones, most `.otf` files, the pdf package cannot embed:
/// their boxes are images). A user font is one face: bold is drawn with
/// a stroke around the glyphs, italic slanted, as on screen.
///
/// Glyph positions come from the app's own layout ([TextLayout]): every
/// word is placed where the canvas draws it, so wrapping, alignment, mixed
/// sizes and list markers match the screen; only the spacing *inside* a
/// left-to-right word comes from the font's advances (no kerning).
/// Right-to-left words (Hebrew, Arabic) and words with characters from the
/// fallback fonts are placed glyph by glyph where the layout put each one,
/// mirrored brackets included; Arabic is written in its contextual
/// presentation forms ([ArabicForms]), its marks centred over their letter
/// (the PDF has no OpenType shaping, so mark positions are approximate).
/// Highlights, underlines, strikethroughs, bullets and checkboxes are
/// vectors. A box with characters the bundled fonts lack (e.g. CJK, emoji,
/// drawn on screen with system fallback fonts) is left to the caller
/// ([draw] returns false), which embeds it as an image instead.
class PdfTextWriter {
  PdfTextWriter(this.doc, {FontAssetLoader? load, this.userFont}) : _load = load ?? rootBundle.load;

  final PdfDocument doc;
  final FontAssetLoader _load;

  /// Reads the files of user fonts (none: their boxes are images).
  final UserFontLoader? userFont;
  final Map<String, Future<PdfTtfFont>> _fonts = {};
  final Map<String, Future<PdfTtfFont?>> _userFonts = {};

  /// Slant of synthetic italics (fonts without an italic face).
  static const double _slant = 0.2;

  /// Stroke width of synthetic bold (user fonts), per unit of font size.
  static const double _embolden = 0.04;

  /// The embedded face of a bundled [font], loaded once per document
  /// (also used for template labels, see `PdfTemplateWriter`).
  Future<PdfTtfFont> font(TextFont font, {required bool bold, required bool italic}) {
    final asset = font.asset(bold: bold, italic: italic);
    return _fonts[asset] ??= _load(asset).then((bytes) => PdfTtfFont(doc, bytes));
  }

  /// The embedded face of [font] as text in it is drawn: a bundled font's,
  /// or a user font's own file while it is shown (else the default font,
  /// as on screen); null for a user font that cannot be embedded.
  Future<PdfTtfFont?> _face(TextFont font, {required bool bold, required bool italic}) {
    if (!TextFonts.isShown(font)) font = TextFont.inter;
    if (!font.isUser) return this.font(font, bold: bold, italic: italic);
    return _userFonts[font.name] ??= _embedUser(font);
  }

  Future<PdfTtfFont?> _embedUser(TextFont font) async {
    final bytes = await userFont?.call(font);
    if (bytes == null || FontFileInfo.read(bytes)?.outlines != FontOutlines.trueType) return null;
    try {
      return PdfTtfFont(doc, ByteData.sublistView(bytes));
    } on Object catch (e) {
      debugPrint('Font ${font.name} cannot be embedded: $e');
      return null;
    }
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
      // Table cells: each laid out on its own, at its place in its row.
      final cells = <(Offset, List<_Run>)>[];
      for (final row in layout.rows) {
        final t = layout.tables[row.table];
        for (var c = 0; c < t.table.columns; c++) {
          final cell = t.cells[t.index(row.row, c)];
          final cellRuns = await _runs(cell.data, cell);
          if (cellRuns == null) return false;
          cells.add((t.textOrigin(row.rect, row.row, c), cellRuns));
        }
      }
      g
        ..saveContext()
        ..setTransform(_boxToPdf(element, pageHeight, k));
      // A table row taller than a page is cut at its box's frame.
      if (ShownTextLayout.cutRow(layout, element.rect.height) != null) {
        g
          ..drawRect(0, 0, element.rect.width, element.rect.height)
          ..clipPath();
      }
      _paint(g, runs);
      await _markers(g, layout);
      for (final (origin, cellRuns) in cells) {
        g
          ..saveContext()
          ..setTransform(Matrix4.translationValues(origin.dx, origin.dy, 0));
        _paint(g, cellRuns);
        g.restoreContext();
      }
      _grids(g, layout);
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
  /// a character is missing from the bundled fonts.
  Future<List<_Run>?> _runs(TextData data, TextBoxLayout layout) async {
    final lines = layout.painter.computeLineMetrics();
    final chars = data.charStyles();
    final paras = data.paras;
    final text = data.text;
    final runs = <_Run>[];
    var lineStart = 0;
    for (var line = 0; line < paras.length; line++) {
      final nl = text.indexOf('\n', lineStart);
      final end = nl < 0 ? text.length : nl;
      final para = paras[line];
      if (para.isCell) {
        // (Written with its own layout, see [draw].)
        lineStart = end + 1;
        continue;
      }
      var i = lineStart;
      while (i < end) {
        var j = i + 1;
        while (j < end && chars[j] == chars[i]) {
          j++;
        }
        final span = chars[i];
        final bold = span.bold || para.heading > 0;
        final run = _Run(style: TextLayout.styleFor(data, span, para), boxes: _boxes(layout, i, j));
        final chosen = span.font ?? data.font;
        final shown = TextFonts.isShown(chosen) ? chosen : TextFont.inter;
        final primary = await _face(shown, bold: bold, italic: span.italic);
        if (primary == null) return null;
        final fonts = _Fonts(
          primary,
          [for (final f in FallbackFont.values) await fallback(f, bold: bold)],
          italic: span.italic,
          hasItalic: shown.hasItalic,
          embolden: bold && shown.isUser,
        );
        // Each word separately, at its laid-out position.
        for (final m in RegExp(r'\S+').allMatches(text.substring(i, j))) {
          final placed = _GlyphPlacer(layout, lines, text, run, fonts).word(i + m.start, i + m.end);
          if (!placed) return null;
        }
        runs.add(run);
        i = j;
      }
      lineStart = end + 1;
    }
    return runs;
  }

  /// The embedded face of a bundled [FallbackFont] (Arabic, Hebrew),
  /// loaded once per document.
  Future<PdfTtfFont> fallback(FallbackFont font, {required bool bold}) {
    final asset = font.asset(bold: bold);
    return _fonts[asset] ??= _load(asset).then((bytes) => PdfTtfFont(doc, bytes));
  }

  /// Laid-out boxes of the text [start, end) (model offsets, one line of
  /// the box's text), without what the layout inserts (breaks, gaps) and
  /// without paragraph spacing below them (highlights end at the text, as
  /// on the canvas).
  static List<Rect> _boxes(TextBoxLayout layout, int start, int end) => [
    for (final b in _textBoxes(layout, start, end)) layout.withoutSpacing(b.toRect()),
  ];

  static List<TextBox> _textBoxes(TextBoxLayout layout, int start, int end) =>
      layout.boxesOf(start, end, boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle);

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
  _Run({required this.style, required this.boxes});

  final TextStyle style;

  /// Laid-out boxes of the whole run (highlight, decorations).
  final List<Rect> boxes;

  /// Words (or single glyphs) with their face, left edge and baseline (box
  /// coordinates), and whether they are slanted (synthetic italic) and
  /// stroked (synthetic bold).
  final List<({String text, PdfTtfFont font, double x, double baseline, bool slant, bool bold})>
  words = [];
}
