import 'dart:ui' show TextDirection;

/// The direction of each paragraph of a text box, from its text alone
/// (Unicode bidi rules P2 / P3: the first strong character decides).
///
/// A paragraph without a strong character (empty, digits, punctuation)
/// takes the direction of the paragraph before it, so pressing Enter in
/// Hebrew keeps the caret on the right; leading ones take the first
/// direction that follows; a box without any strong character is
/// left-to-right.
abstract final class ParagraphDirection {
  static const int _lri = 0x2066, _rli = 0x2067, _fsi = 0x2068, _pdi = 0x2069;

  /// The direction of [text]'s first strong character in [start, end)
  /// outside isolates, or null if it has none.
  static TextDirection? firstStrong(String text, [int start = 0, int? end]) {
    final stop = end ?? text.length;
    var isolates = 0;
    var i = start;
    while (i < stop) {
      var c = text.codeUnitAt(i++);
      if (c >= 0xD800 && c <= 0xDBFF && i < stop) {
        c = 0x10000 + ((c - 0xD800) << 10) + (text.codeUnitAt(i++) - 0xDC00);
      }
      if (c == _lri || c == _rli || c == _fsi) {
        isolates++;
      } else if (c == _pdi) {
        if (isolates > 0) isolates--;
      } else if (isolates == 0) {
        final d = strongDirection(c);
        if (d != null) return d;
      }
    }
    return null;
  }

  /// The directions of the paragraphs (lines split by `\n`) of [text].
  static List<TextDirection> of(String text) {
    final found = <TextDirection?>[];
    var start = 0;
    while (true) {
      final nl = text.indexOf('\n', start);
      final end = nl < 0 ? text.length : nl;
      found.add(firstStrong(text, start, end));
      if (nl < 0) break;
      start = nl + 1;
    }
    var last = found.firstWhere((d) => d != null, orElse: () => null) ?? TextDirection.ltr;
    return [for (final d in found) last = d ?? last];
  }

  /// The direction of the box as a whole: its first paragraph's.
  static TextDirection baseOf(String text) => firstStrong(text) ?? TextDirection.ltr;

  /// The bidi direction of code point [c] if it is strong (bidi classes L,
  /// R and AL), else null.
  ///
  /// Letters are strong: right-to-left in the Hebrew, Arabic, Syriac,
  /// Thaana, N'Ko, Samaritan, Mandaic and other right-to-left blocks,
  /// left-to-right elsewhere. Digits, punctuation, symbols, spaces and
  /// combining marks are not.
  static TextDirection? strongDirection(int c) {
    if (c < 0x80) {
      final lower = c | 0x20;
      return lower >= 0x61 && lower <= 0x7A ? TextDirection.ltr : null;
    }
    if (c == 0x200E) return TextDirection.ltr; // LRM
    if (c == 0x200F || c == 0x061C) return TextDirection.rtl; // RLM, ALM
    if (!_letter.hasMatch(String.fromCharCode(c))) return null;
    return _isRtlBlock(c) ? TextDirection.rtl : TextDirection.ltr;
  }

  static final RegExp _letter = RegExp(r'^[\p{L}\p{Mc}]$', unicode: true);

  static bool _isRtlBlock(int c) =>
      (c >= 0x0590 && c <= 0x08FF) || // Hebrew … Arabic Extended-A
      (c >= 0xFB1D && c <= 0xFDFF) || // Hebrew / Arabic presentation forms A
      (c >= 0xFE70 && c <= 0xFEFF) || // Arabic presentation forms B
      (c >= 0x10800 && c <= 0x10FFF) || // historic right-to-left scripts
      (c >= 0x1E800 && c <= 0x1EFFF); // Adlam, Arabic mathematical, …
}
