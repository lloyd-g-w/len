import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../domain/notebook_page.dart';
import 'pdf_page_info.dart';

/// Hit testing on the characters of a PDF page (normalised coordinates:
/// 0..1 from the page's left and top edges).
extension PdfGlyphHits on PdfGlyphs {
  /// The character under [p], or the nearest one on the line under it
  /// within [slop] (horizontally); null if there is no text there.
  int? indexAt(Offset p, {double slop = 0.02}) {
    int? best;
    var bestDistance = double.infinity;
    for (var i = 0; i < boxes.length; i++) {
      final box = boxes[i];
      if (box.isEmpty) continue;
      if (box.contains(p)) return i;
      if (p.dy < box.top || p.dy > box.bottom) continue; // Another line.
      final d = p.dx < box.left ? box.left - p.dx : p.dx - box.right;
      if (d <= slop && d < bestDistance) {
        best = i;
        bestDistance = d;
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
      // Lines first: vertical distance weighs more than horizontal.
      final dx = math.max(0.0, math.max(box.left - p.dx, p.dx - box.right));
      final dy = math.max(0.0, math.max(box.top - p.dy, p.dy - box.bottom));
      final d = dy * 4 + dx;
      if (d < bestDistance) {
        best = i;
        bestDistance = d;
      }
    }
    return best;
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

/// The PDF text selected on one page: `text[start, end)` of [glyphs].
class PdfSelection extends ChangeNotifier {
  NotebookPage? _page;
  PdfGlyphs? _glyphs;
  int _start = 0, _end = 0;
  bool _menu = false;

  /// The page the selection is on; null when nothing is selected.
  NotebookPage? get page => _page;
  PdfGlyphs? get glyphs => _glyphs;
  int get start => _start;
  int get end => _end;
  bool get isEmpty => _page == null || _end <= _start;

  /// Whether the selection's menu (copy, highlight) is offered: after the
  /// pointer lifted.
  bool get showsMenu => _menu && !isEmpty;

  /// The selected text, with surrounding whitespace removed.
  String get text => isEmpty ? '' : _glyphs!.text.substring(_start, _end).trim();

  /// One box per selected line, normalised to the page.
  List<Rect> get rects => isEmpty ? const [] : _glyphs!.rectsFor(_start, _end);

  /// Selects `[start, end)` (in either order) of [glyphs] on [page].
  void select(NotebookPage page, PdfGlyphs glyphs, int start, int end, {bool menu = false}) {
    final a = math.min(start, end).clamp(0, glyphs.text.length);
    final b = math.max(start, end).clamp(0, glyphs.text.length);
    if (identical(page, _page) && a == _start && b == _end && menu == _menu) return;
    _page = page;
    _glyphs = glyphs;
    _start = a;
    _end = b;
    _menu = menu;
    notifyListeners();
  }

  /// Offers (or hides) the menu for the current selection.
  set showsMenu(bool value) {
    if (value == _menu) return;
    _menu = value;
    notifyListeners();
  }

  void clear() {
    if (_page == null) return;
    _page = null;
    _glyphs = null;
    _start = _end = 0;
    _menu = false;
    notifyListeners();
  }
}
