/// Contextual shaping of Arabic for PDF export, where text is written with
/// a font's character map only (no OpenType shaping): each letter becomes
/// its isolated, final, initial or medial presentation form (Unicode
/// Arabic Presentation Forms A / B, which the bundled Noto Sans Arabic
/// maps to its shaped glyphs) by how it joins its neighbours, and lam
/// followed by alef becomes their ligature.
///
/// Covers Arabic, Persian and Urdu letters with presentation forms; other
/// characters pass through unchanged. Marks keep their code points (they
/// are placed over their letter by the caller).
abstract final class ArabicForms {
  static const int _lam = 0x0644;
  static const int _tatweel = 0x0640;

  /// Dual-joining letters → their isolated form (final, initial and medial
  /// follow it).
  static const Map<int, int> _dual = {
    0x0626: 0xFE89, 0x0628: 0xFE8F, 0x062A: 0xFE95, 0x062B: 0xFE99, 0x062C: 0xFE9D, //
    0x062D: 0xFEA1, 0x062E: 0xFEA5, 0x0633: 0xFEB1, 0x0634: 0xFEB5, 0x0635: 0xFEB9,
    0x0636: 0xFEBD, 0x0637: 0xFEC1, 0x0638: 0xFEC5, 0x0639: 0xFEC9, 0x063A: 0xFECD,
    0x0641: 0xFED1, 0x0642: 0xFED5, 0x0643: 0xFED9, 0x0644: 0xFEDD, 0x0645: 0xFEE1,
    0x0646: 0xFEE5, 0x0647: 0xFEE9, 0x064A: 0xFEF1,
    // Persian and Urdu (presentation forms A).
    0x067E: 0xFB56, 0x0679: 0xFB66, 0x0686: 0xFB7A, 0x06A9: 0xFB8E, 0x06AF: 0xFB92,
    0x06BE: 0xFBAA, 0x06C1: 0xFBA6, 0x06CC: 0xFBFC,
  };

  /// Right-joining letters (they join the letter before only) → their
  /// isolated form (the final form follows it).
  static const Map<int, int> _right = {
    0x0622: 0xFE81, 0x0623: 0xFE83, 0x0624: 0xFE85, 0x0625: 0xFE87, 0x0627: 0xFE8D, //
    0x0629: 0xFE93, 0x062F: 0xFEA9, 0x0630: 0xFEAB, 0x0631: 0xFEAD, 0x0632: 0xFEAF,
    0x0648: 0xFEED, 0x0649: 0xFEEF,
    0x0688: 0xFB88, 0x0691: 0xFB8C, 0x0698: 0xFB8A, 0x06BA: 0xFB9E, 0x06D2: 0xFBAE,
  };

  /// Lam followed by these alefs → the isolated ligature (final follows).
  static const Map<int, int> _lamAlef = {
    0x0622: 0xFEF5,
    0x0623: 0xFEF7,
    0x0625: 0xFEF9,
    0x0627: 0xFEFB,
  };

  /// Whether [c] is an Arabic mark, transparent to joining.
  static bool isMark(int c) =>
      (c >= 0x0610 && c <= 0x061A) ||
      (c >= 0x064B && c <= 0x065F) ||
      c == 0x0670 ||
      (c >= 0x06D6 && c <= 0x06ED && c != 0x06DD && c != 0x06DE && c != 0x06E9);

  static bool _joinsAfter(int c) => _dual.containsKey(c) || c == _tatweel;
  static bool _joinsBefore(int c) => _dual.containsKey(c) || _right.containsKey(c) || c == _tatweel;

  /// [text] (logical order, UTF-16 code units of the Basic Multilingual
  /// Plane) from [from] to [to] (all of it by default) shaped: the glyphs
  /// to draw, each with the range [start, end) of [text] it stands for, in
  /// logical order. Letters join their neighbours outside the range too (a
  /// differently formatted part of a word joins as on screen); lam and
  /// alef form their ligature only both inside it.
  static List<({String glyph, int start, int end})> shape(String text, [int from = 0, int? to]) {
    final units = text.codeUnits;
    final end = to ?? units.length;
    int? neighbour(int i, int step) {
      for (var k = i + step; k >= 0 && k < units.length; k += step) {
        if (!isMark(units[k])) return k;
      }
      return null;
    }

    final out = <({String glyph, int start, int end})>[];
    var i = from;
    while (i < end) {
      final c = units[i];
      final before = neighbour(i, -1);
      final joinsPrev = before != null && _joinsAfter(units[before]) && _joinsBefore(c);
      final next = neighbour(i, 1);
      if (c == _lam && next != null && next < end && _lamAlef.containsKey(units[next])) {
        // The ligature stands for lam, the alef and the marks between;
        // those marks follow it.
        final glyph = _lamAlef[units[next]]! + (joinsPrev ? 1 : 0);
        out.add((glyph: String.fromCharCode(glyph), start: i, end: next + 1));
        for (var k = i + 1; k < next; k++) {
          out.add((glyph: String.fromCharCode(units[k]), start: k, end: k + 1));
        }
        i = next + 1;
        continue;
      }
      final dual = _dual[c], right = _right[c];
      if (dual == null && right == null) {
        out.add((glyph: String.fromCharCode(c), start: i, end: i + 1));
        i++;
        continue;
      }
      final joinsNext = dual != null && next != null && _joinsBefore(units[next]);
      final form = switch ((joinsPrev, joinsNext)) {
        (true, true) => 3,
        (false, true) => 2,
        (true, false) => 1,
        (false, false) => 0,
      };
      out.add((glyph: String.fromCharCode((dual ?? right)! + form), start: i, end: i + 1));
      i++;
    }
    return out;
  }
}
