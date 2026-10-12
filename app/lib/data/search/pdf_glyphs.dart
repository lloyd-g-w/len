import 'dart:math' as math;
import 'dart:ui';

/// The direction a line of PDF text reads in on screen: left to right,
/// top to bottom (a page turned a quarter clockwise), right to left
/// (upside down) or bottom to top.
enum PdfTextDirection {
  ltr,
  ttb,
  rtl,
  btt;

  /// Whether the line runs up or down the screen.
  bool get vertical => this == ttb || this == btt;

  /// The unit vector from the top of the line's letters to their bottom.
  Offset get down => switch (this) {
    ltr => const Offset(0, 1),
    ttb => const Offset(-1, 0),
    rtl => const Offset(0, -1),
    btt => const Offset(1, 0),
  };
}

/// A run of characters on one line: `text[start, end)` and the box around
/// them (normalised to the page).
class PdfTextLine {
  const PdfTextLine(this.start, this.end, this.rect, this.direction);

  final int start, end;
  final Rect rect;
  final PdfTextDirection direction;

  /// The extent across the line (the height of its letters), normalised.
  double get thickness => direction.vertical ? rect.width : rect.height;

  /// The corner where the line starts (at the top of its letters) and the
  /// one where it ends (at their bottom).
  Offset get startCorner => switch (direction) {
    PdfTextDirection.ltr => rect.topLeft,
    PdfTextDirection.ttb => rect.topRight,
    PdfTextDirection.rtl => rect.bottomRight,
    PdfTextDirection.btt => rect.bottomLeft,
  };
  Offset get endCorner => switch (direction) {
    PdfTextDirection.ltr => rect.bottomRight,
    PdfTextDirection.ttb => rect.bottomLeft,
    PdfTextDirection.rtl => rect.topLeft,
    PdfTextDirection.btt => rect.topRight,
  };

  @override
  String toString() => 'PdfTextLine($start, $end, $rect, $direction)';
}

/// A page's text and the box of every UTF-16 unit of it.
///
/// Boxes are normalised to the page as shown (rotation applied), so on a
/// turned page — or for text set at an angle — lines may run down, up or
/// right to left; [lines] finds each line and its direction from the boxes.
class PdfGlyphs {
  PdfGlyphs(this.text, this.boxes) : assert(text.length == boxes.length);

  final String text;

  /// Normalised (0..1, top-left origin) box of each unit of [text].
  final List<Rect> boxes;

  /// The page's lines, in text order (characters without a box belong to
  /// none).
  late final List<PdfTextLine> lines = _layout();

  late final List<int> _lineOf = () {
    final of = List.filled(text.length, -1);
    for (final (k, line) in lines.indexed) {
      for (var i = line.start; i < line.end; i++) {
        if (_boxed(i)) of[i] = k;
      }
    }
    return of;
  }();

  /// The line character [i] is on; null for characters without a box.
  PdfTextLine? lineOf(int i) {
    final k = i < 0 || i >= _lineOf.length ? -1 : _lineOf[i];
    return k < 0 ? null : lines[k];
  }

  /// The parts of [lines] covering `text[start..end)`, one per line.
  List<PdfTextLine> linesFor(int start, int end) {
    final result = <PdfTextLine>[];
    var current = -1;
    for (var i = start.clamp(0, boxes.length); i < end.clamp(0, boxes.length); i++) {
      final k = _lineOf[i];
      if (k < 0) continue; // Spaces and line breaks have no box.
      if (k == current) {
        final last = result.last;
        result.last = PdfTextLine(
          last.start,
          i + 1,
          last.rect.expandToInclude(boxes[i]),
          last.direction,
        );
      } else {
        current = k;
        result.add(PdfTextLine(i, i + 1, boxes[i], lines[k].direction));
      }
    }
    return result;
  }

  /// Boxes covering `text[start..end)`, merged into one per line.
  List<Rect> rectsFor(int start, int end) => [for (final l in linesFor(start, end)) l.rect];

  /// Whether character [i] takes part in lines: it has a box and is not
  /// white space (whose boxes PDFium places loosely).
  bool _boxed(int i) => !boxes[i].isEmpty && text[i].trim().isNotEmpty;

  List<PdfTextLine> _layout() {
    final lines = <PdfTextLine>[];
    int? start, last;
    var rect = Rect.zero;
    PdfTextDirection? direction;
    void close() {
      if (start == null) return;
      lines.add(PdfTextLine(start, last! + 1, rect, direction ?? PdfTextDirection.ltr));
    }

    var broken = false;
    for (var i = 0; i < boxes.length; i++) {
      final box = boxes[i];
      if (text[i] == '\n' || text[i] == '\r') broken = true;
      if (!_boxed(i)) continue;
      if (start != null && broken) {
        close();
        start = null;
      }
      broken = false;
      if (start != null) {
        final step = _step(boxes[last!], box);
        final joins = switch (step) {
          null => true, // On top of the previous character.
          final d when direction != null && d != direction => false,
          final d => _overlapAcross(rect, box, d.vertical),
        };
        if (joins) {
          direction ??= step;
          rect = rect.expandToInclude(box);
          last = i;
          continue;
        }
        close();
      }
      start = last = i;
      rect = box;
      direction = null;
    }
    close();
    return lines;
  }

  /// The direction from character box [a] to the next one [b]; null if
  /// they are (almost) at the same place.
  static PdfTextDirection? _step(Rect a, Rect b) {
    final d = b.center - a.center;
    final size = math.min(math.min(a.shortestSide, b.shortestSide), 1.0);
    if (d.distance < 0.2 * size) return null;
    if (d.dx.abs() >= d.dy.abs()) return d.dx > 0 ? PdfTextDirection.ltr : PdfTextDirection.rtl;
    return d.dy > 0 ? PdfTextDirection.ttb : PdfTextDirection.btt;
  }

  /// Whether [box] lies on the line [line] (more than half of the smaller
  /// extent across the line overlaps).
  static bool _overlapAcross(Rect line, Rect box, bool vertical) {
    final (a0, a1, b0, b1) = vertical
        ? (line.left, line.right, box.left, box.right)
        : (line.top, line.bottom, box.top, box.bottom);
    final overlap = math.min(a1, b1) - math.max(a0, b0);
    return overlap > 0.5 * math.min(a1 - a0, b1 - b0);
  }
}
