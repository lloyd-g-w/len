import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../domain/notebook_page.dart';
import 'pdf_page_info.dart';

/// Hit testing on the characters of a PDF page (normalised coordinates:
/// 0..1 from the page's left and top edges).
extension PdfGlyphHits on PdfGlyphs {
  /// The character under [p], or the nearest one on the line under it
  /// within [slop] (along the line); null if there is no text there.
  int? indexAt(Offset p, {double slop = 0.02}) {
    int? best;
    var bestDistance = double.infinity;
    for (var i = 0; i < boxes.length; i++) {
      final box = boxes[i];
      if (box.isEmpty) continue;
      if (box.contains(p)) return i;
      final (along, across) = _distances(box, p, lineOf(i)?.direction.vertical ?? false);
      if (across > 0) continue; // Another line.
      if (along <= slop && along < bestDistance) {
        best = i;
        bestDistance = along;
      }
    }
    return best;
  }

  /// The character nearest to [p] (to extend a selection wherever the
  /// pointer goes); null without any text.
  int? nearestIndex(Offset p) {
    int? best;
    var bestDistance = double.infinity;
    for (var i = 0; i < boxes.length; i++) {
      final box = boxes[i];
      if (box.isEmpty) continue;
      // Lines first: the distance across lines weighs more than along them.
      final (along, across) = _distances(box, p, lineOf(i)?.direction.vertical ?? false);
      final d = across * 4 + along;
      if (d < bestDistance) {
        best = i;
        bestDistance = d;
      }
    }
    return best;
  }

  /// How far [p] is from [box] along and across a line running down the
  /// screen if [vertical], else across it.
  static (double, double) _distances(Rect box, Offset p, bool vertical) {
    final dx = math.max(0.0, math.max(box.left - p.dx, p.dx - box.right));
    final dy = math.max(0.0, math.max(box.top - p.dy, p.dy - box.bottom));
    return vertical ? (dy, dx) : (dx, dy);
  }

  /// The word (letters, digits and joiners) around character [i], as
  /// `[start, end)`; just the character itself if it is not part of one.
  (int, int) wordAt(int i) {
    bool isWord(int j) => _wordChar.hasMatch(text[j]);
    if (i < 0 || i >= text.length || !isWord(i)) return (i, math.min(i + 1, text.length));
    var start = i, end = i + 1;
    while (start > 0 && isWord(start - 1)) {
      start--;
    }
    while (end < text.length && isWord(end)) {
      end++;
    }
    return (start, end);
  }

  static final _wordChar = RegExp(r"[\p{L}\p{N}\p{M}_'’-]", unicode: true);
}

/// One page's part of a PDF text selection: `text[start, end)` of [glyphs].
@immutable
class PdfSpan {
  const PdfSpan(this.page, this.glyphs, this.start, this.end);

  final NotebookPage page;
  final PdfGlyphs glyphs;
  final int start, end;

  bool get isEmpty => end <= start;

  /// The selected text, with surrounding whitespace removed.
  String get text => isEmpty ? '' : glyphs.text.substring(start, end).trim();

  /// The selected part of each line (with its direction).
  List<PdfTextLine> get lines => isEmpty ? const [] : glyphs.linesFor(start, end);
}

/// The PDF text selected: one span per page, in page order — a selection
/// can run from a line on one page to a line on a later one, the pages in
/// between taken whole.
class PdfSelection extends ChangeNotifier {
  List<PdfSpan> _spans = const [];
  bool _menu = false;

  /// The selected parts of each page, in page order.
  List<PdfSpan> get spans => _spans;

  /// The page the selection starts on; null when nothing is selected.
  NotebookPage? get page => _spans.isEmpty ? null : _spans.first.page;
  PdfGlyphs? get glyphs => _spans.isEmpty ? null : _spans.first.glyphs;

  /// Where the selection starts (on [page]) and ends (on the last span's
  /// page).
  int get start => _spans.isEmpty ? 0 : _spans.first.start;
  int get end => _spans.isEmpty ? 0 : _spans.last.end;
  bool get isEmpty => _spans.every((s) => s.isEmpty);

  /// Whether the selection runs over more than one page.
  bool get spansPages => _spans.length > 1;

  /// Whether the selection's menu (copy, highlight) is offered: after the
  /// pointer lifted.
  bool get showsMenu => _menu && !isEmpty;

  /// The selected text, pages joined by a blank line, with surrounding
  /// whitespace removed.
  String get text => [
    for (final s in _spans)
      if (s.text.isNotEmpty) s.text,
  ].join('\n\n');

  /// One box per selected line of the first page, normalised to it.
  List<Rect> get rects => [for (final l in lines) l.rect];

  /// The selected part of each line of the first page (with its direction).
  List<PdfTextLine> get lines => _spans.isEmpty ? const [] : _spans.first.lines;

  /// Selects `[start, end)` (in either order) of [glyphs] on [page].
  void select(NotebookPage page, PdfGlyphs glyphs, int start, int end, {bool menu = false}) {
    final a = math.min(start, end).clamp(0, glyphs.text.length);
    final b = math.max(start, end).clamp(0, glyphs.text.length);
    selectSpans([PdfSpan(page, glyphs, a, b)], menu: menu);
  }

  /// Selects [spans] (one per page, in page order).
  void selectSpans(List<PdfSpan> spans, {bool menu = false}) {
    if (_same(spans) && menu == _menu) return;
    _spans = List.unmodifiable(spans);
    _menu = menu;
    notifyListeners();
  }

  bool _same(List<PdfSpan> spans) {
    if (spans.length != _spans.length) return false;
    for (var i = 0; i < spans.length; i++) {
      final a = spans[i], b = _spans[i];
      if (!identical(a.page, b.page) || a.start != b.start || a.end != b.end) return false;
    }
    return true;
  }

  /// Offers (or hides) the menu for the current selection.
  set showsMenu(bool value) {
    if (value == _menu) return;
    _menu = value;
    notifyListeners();
  }

  void clear() {
    if (_spans.isEmpty) return;
    _spans = const [];
    _menu = false;
    notifyListeners();
  }
}
