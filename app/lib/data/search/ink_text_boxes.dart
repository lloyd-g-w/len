import 'dart:convert';
import 'dart:ui';

/// The per-word boxes of a recognised line (`ink_text.words`): JSON
/// `[[x, y, w, h], …]`, one per word of the line's text.
abstract final class InkTextBoxes {
  static String? encode(List<Rect>? words) => words == null
      ? null
      : jsonEncode([
          for (final r in words) [_round(r.left), _round(r.top), _round(r.width), _round(r.height)],
        ]);

  /// The boxes, or null if [json] is missing or malformed.
  static List<Rect>? decode(String? json) {
    if (json == null) return null;
    try {
      final list = jsonDecode(json);
      if (list is! List) return null;
      final rects = <Rect>[];
      for (final item in list) {
        if (item is! List || item.length != 4 || item.any((v) => v is! num)) return null;
        final [x, y, w, h] = [for (final v in item) (v as num).toDouble()];
        rects.add(Rect.fromLTWH(x, y, w, h));
      }
      return rects;
    } on FormatException {
      return null;
    }
  }

  static double _round(double v) => (v * 10).roundToDouble() / 10;

  /// Character ranges of the whitespace-separated words of [text], in order.
  static List<({int start, int end})> wordRanges(String text) => [
    for (final m in RegExp(r'\S+').allMatches(text)) (start: m.start, end: m.end),
  ];
}
