import 'dart:ui';

import '../../../data/search/ink_text_boxes.dart';

/// Where to highlight a match in a recognised line of handwriting.
abstract final class InkMatchRects {
  /// The boxes of the words of [text] that [range] overlaps, when the
  /// line's [words] boxes are known (one per word); else the whole [line].
  static List<Rect> of(String text, ({int start, int end}) range, Rect line, List<Rect>? words) {
    final ranges = InkTextBoxes.wordRanges(text);
    if (words == null || words.length != ranges.length) return [line];
    final hit = [
      for (var i = 0; i < ranges.length; i++)
        if (ranges[i].start < range.end && range.start < ranges[i].end) words[i],
    ];
    return hit.isEmpty ? [line] : hit;
  }
}
