part of 'pdf_text.dart';

/// The faces a run of text can be written in: the run's own bundled font
/// and the fallbacks for scripts it lacks.
class _Fonts {
  _Fonts(this.primary, this.fallbacks, {required this.italic, required this.hasItalic});

  final PdfTtfFont primary;
  final List<PdfTtfFont> fallbacks;
  final bool italic;

  /// Whether [primary] has a real italic face.
  final bool hasItalic;

  /// The face with a glyph for [rune], if any.
  PdfTtfFont? of(int rune) {
    if (_has(primary, rune)) return primary;
    for (final f in fallbacks) {
      if (_has(f, rune)) return f;
    }
    return null;
  }

  static bool _has(PdfTtfFont f, int rune) => f.font.charToGlyphIndexMap.containsKey(rune);

  /// Whether text in [font] is slanted (synthetic italic).
  bool slants(PdfTtfFont font) => italic && (!identical(font, primary) || !hasItalic);
}

/// Places the words of one run: a left-to-right word in its own font
/// whole at its laid-out position, anything else glyph by glyph where the
/// layout put each one.
class _GlyphPlacer {
  _GlyphPlacer(this.layout, this.lines, this.text, this.run, this.fonts);

  final TextBoxLayout layout;
  final List<ui.LineMetrics> lines;
  final String text;
  final _Run run;
  final _Fonts fonts;

  /// Characters that need no glyph (format controls) when missing.
  static bool _invisible(int rune) =>
      rune <= 0x20 ||
      (rune >= 0x200B && rune <= 0x200F) ||
      (rune >= 0x2066 && rune <= 0x2069) ||
      rune == 0x061C ||
      rune == 0xFEFF;

  /// Hebrew points and cantillation marks.
  static bool _hebrewMark(int c) =>
      (c >= 0x0591 && c <= 0x05BD) ||
      c == 0x05BF ||
      c == 0x05C1 ||
      c == 0x05C2 ||
      c == 0x05C4 ||
      c == 0x05C5 ||
      c == 0x05C7;

  static bool _isMark(int c) => _hebrewMark(c) || ArabicForms.isMark(c);

  static bool _isArabic(int c) => c >= 0x0600 && c <= 0x06FF;

  /// Brackets and the like shown mirrored in right-to-left text.
  static const Map<int, int> _mirrors = {
    0x28: 0x29, 0x29: 0x28, 0x3C: 0x3E, 0x3E: 0x3C, 0x5B: 0x5D, 0x5D: 0x5B, //
    0x7B: 0x7D, 0x7D: 0x7B, 0xAB: 0xBB, 0xBB: 0xAB, 0x2039: 0x203A, 0x203A: 0x2039,
    0x2264: 0x2265, 0x2265: 0x2264,
  };

  /// Adds the word [start, end) (model offsets) to the run; false if a
  /// character has no glyph in the bundled fonts.
  bool word(int start, int end) {
    final word = text.substring(start, end);
    for (final r in word.runes) {
      if (fonts.of(r) == null && !_invisible(r)) return false;
    }
    final boxes = PdfTextWriter._textBoxes(layout, start, end);
    if (boxes.isEmpty) return true;
    final plain =
        boxes.length == 1 &&
        boxes.single.direction == TextDirection.ltr &&
        word.runes.every((r) => identical(fonts.of(r), fonts.primary));
    if (plain) {
      final box = boxes.single.toRect();
      _add(word, fonts.primary, box.left, box);
      return true;
    }
    _glyphs(start, word);
    return true;
  }

  /// The word at [start] glyph by glyph: Arabic shaped (joining the
  /// letters around it, in other runs), marks over their letter, brackets
  /// mirrored in right-to-left runs.
  void _glyphs(int start, String word) {
    final glyphs = word.codeUnits.any(_isArabic)
        ? [
            for (final g in ArabicForms.shape(text, start, start + word.length))
              (glyph: g.glyph, start: g.start - start, end: g.end - start),
          ]
        : [
            for (var i = 0; i < word.length; i++)
              if (!_isLow(word.codeUnitAt(i)))
                (glyph: word.substring(i, i + _units(word, i)), start: i, end: i + _units(word, i)),
          ];
    Rect? last;
    for (final g in glyphs) {
      final rune = g.glyph.runes.first;
      final source = word.substring(g.start, g.end).runes.first;
      var boxes = PdfTextWriter._textBoxes(layout, start + g.start, start + g.end);
      if (boxes.isEmpty && !_isMark(rune)) {
        // A letter laid out with its marks as one cluster: their box.
        var end = g.end;
        while (end < word.length && _isMark(word.codeUnitAt(end))) {
          end++;
        }
        boxes = PdfTextWriter._textBoxes(layout, start + g.start, start + end);
      }
      final rect = boxes.isEmpty ? null : _union(boxes);
      if (_isMark(rune)) {
        final base = rect != null && rect.width > 0.01 ? rect : last;
        if (base == null) continue;
        final font = fonts.of(rune) ?? fonts.primary;
        final m = font.glyphMetrics(rune);
        final size = run.style.fontSize!;
        _add(g.glyph, font, base.center.dx - (m.left + m.right) / 2 * size, base);
        continue;
      }
      if (rect == null || _invisible(rune)) continue;
      final rtl = boxes.first.direction == TextDirection.rtl;
      var draw = rtl ? (_mirrors[rune] ?? rune) : rune;
      var font = fonts.of(draw);
      if (font == null) {
        // A shaped form the font lacks: its letter as it is.
        draw = source;
        font = fonts.of(draw);
      }
      if (font == null) continue;
      _add(String.fromCharCode(draw), font, rect.left, rect);
      last = rect;
    }
  }

  static bool _isLow(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  static int _units(String s, int i) {
    final u = s.codeUnitAt(i);
    return u >= 0xD800 && u <= 0xDBFF && i + 1 < s.length ? 2 : 1;
  }

  /// The boxes of one glyph on its first line, joined.
  static Rect _union(List<TextBox> boxes) {
    var r = boxes.first.toRect();
    for (final b in boxes.skip(1)) {
      if ((b.top - boxes.first.top).abs() > 0.5) continue;
      r = r.expandToInclude(b.toRect());
    }
    return r;
  }

  void _add(String glyph, PdfTtfFont font, double x, Rect box) => run.words.add((
    text: glyph,
    font: font,
    x: x,
    baseline: PdfTextWriter._baseline(lines, box),
    slant: fonts.slants(font),
  ));
}
