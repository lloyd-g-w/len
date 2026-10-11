import 'dart:math' as math;
import 'dart:ui';

import 'paper.dart';

/// How prominent a pattern line is.
enum PatternWeight {
  /// Ordinary ruling, grid and staff lines.
  normal,

  /// Structural lines (Cornell sections).
  heavy,

  /// The red margin line of ruled paper.
  margin,
}

/// One straight pattern line in world coordinates.
typedef PatternLine = ({Offset a, Offset b, PatternWeight weight});

/// The geometry of a paper template within an area, independent of how it
/// is drawn (on screen, in thumbnails, or into an exported PDF).
class PaperPattern {
  const PaperPattern({this.lines = const [], this.dots = const []});

  final List<PatternLine> lines;
  final List<Offset> dots;

  bool get isEmpty => lines.isEmpty && dots.isEmpty;

  /// Pattern pieces of [style] intersecting [area] (world coordinates).
  ///
  /// [page] is the page rectangle (pages have margins and sections), or
  /// null for an infinite canvas, where the pattern tiles forever.
  static PaperPattern of(PaperStyle style, Rect area, {Rect? page}) {
    final region = page == null ? area : area.intersect(page);
    if (region.isEmpty || style.spacing <= 0) return const PaperPattern();
    final b = _Builder(style.spacing, region, page);
    switch (style) {
      case PaperStyle.blank:
        break;
      case PaperStyle.wideRuled || PaperStyle.collegeRuled || PaperStyle.narrowRuled:
        b.ruled();
      case PaperStyle.gridLarge || PaperStyle.gridSmall:
        b.grid();
      case PaperStyle.dotted:
        b.dotted();
      case PaperStyle.isometric:
        b.isometric();
      case PaperStyle.cornell:
        page == null ? b.ruled() : b.cornell(page);
      case PaperStyle.music:
        b.music();
    }
    return PaperPattern(lines: b.lines, dots: b.dots);
  }
}

class _Builder {
  _Builder(this.s, this.area, this.page);

  /// Pattern pitch.
  final double s;
  final Rect area;
  final Rect? page;
  final List<PatternLine> lines = [];
  final List<Offset> dots = [];

  /// Header space above the first ruled line on a page.
  double get _top => (page?.top ?? 0) + 3 * s;

  void _h(double y, double x0, double x1, [PatternWeight w = PatternWeight.normal]) {
    final from = math.max(x0, area.left), to = math.min(x1, area.right);
    if (y < area.top || y > area.bottom || from >= to) return;
    lines.add((a: Offset(from, y), b: Offset(to, y), weight: w));
  }

  void _v(double x, double y0, double y1, [PatternWeight w = PatternWeight.normal]) {
    final from = math.max(y0, area.top), to = math.min(y1, area.bottom);
    if (x < area.left || x > area.right || from >= to) return;
    lines.add((a: Offset(x, from), b: Offset(x, to), weight: w));
  }

  /// Multiples of [step] (offset by [origin]) within [from, to].
  Iterable<double> _ticks(double from, double to, double step, [double origin = 0]) sync* {
    for (var v = ((from - origin) / step).ceil() * step + origin; v <= to; v += step) {
      yield v;
    }
  }

  void ruled({double? bottom}) {
    final page = this.page;
    final start = page == null ? area.top : math.max(area.top, _top);
    for (final y in _ticks(start, bottom ?? area.bottom, s)) {
      _h(y, area.left, area.right);
    }
    if (page != null) _v(page.left + 80, page.top, page.bottom, PatternWeight.margin);
  }

  void grid() {
    for (final y in _ticks(area.top, area.bottom, s)) {
      _h(y, area.left, area.right);
    }
    for (final x in _ticks(area.left, area.right, s)) {
      _v(x, area.top, area.bottom);
    }
  }

  void dotted() {
    for (final y in _ticks(area.top, area.bottom, s)) {
      for (final x in _ticks(area.left, area.right, s)) {
        dots.add(Offset(x, y));
      }
    }
  }

  /// Lines at 0°, 60° and 120° forming equilateral triangles of side [s].
  void isometric() {
    final h = s * math.sqrt(3) / 2;
    for (final y in _ticks(area.top, area.bottom, h)) {
      _h(y, area.left, area.right);
    }
    // Slanted lines x = c ± y / √3 for c a multiple of s; clip to the area.
    final k = 1 / math.sqrt(3);
    for (final sign in const [1.0, -1.0]) {
      final cs = [
        area.left - sign * area.top * k,
        area.right - sign * area.top * k,
        area.left - sign * area.bottom * k,
        area.right - sign * area.bottom * k,
      ];
      for (final c in _ticks(cs.reduce(math.min), cs.reduce(math.max), s)) {
        final seg = _clipSlanted(c, sign * k);
        if (seg != null) lines.add((a: seg.$1, b: seg.$2, weight: PatternWeight.normal));
      }
    }
  }

  /// The part of the line x = c + m·y inside [area].
  (Offset, Offset)? _clipSlanted(double c, double m) {
    // y range where x is inside [left, right].
    var y0 = (area.left - c) / m, y1 = (area.right - c) / m;
    if (y0 > y1) (y0, y1) = (y1, y0);
    final top = math.max(y0, area.top), bottom = math.min(y1, area.bottom);
    if (top >= bottom) return null;
    return (Offset(c + m * top, top), Offset(c + m * bottom, bottom));
  }

  /// Cornell notes: header, cue column, note lines and a summary box.
  void cornell(Rect page) {
    final header = page.top + 3 * s;
    final summary = page.top + page.height * 0.78;
    final cue = page.left + page.width * 0.3;
    ruled(bottom: summary - s / 2);
    lines.removeWhere((l) => l.weight == PatternWeight.margin);
    _h(header, page.left, page.right, PatternWeight.heavy);
    _h(summary, page.left, page.right, PatternWeight.heavy);
    _v(cue, header, summary, PatternWeight.heavy);
  }

  /// Five-line staves; [s] is the distance between staff lines.
  void music() {
    final page = this.page;
    final period = 4 * s + 7 * s; // Staff height plus the gap to the next.
    final origin = page == null ? 0.0 : page.top + 6 * s;
    final left = page == null ? area.left : page.left + 48;
    final right = page == null ? area.right : page.right - 48;
    final end = page == null ? area.bottom : page.bottom - 4 * s;
    final from = page == null ? area.top - 4 * s : math.max(area.top - 4 * s, origin);
    for (final top in _ticks(from, math.min(area.bottom, end - 4 * s), period, origin)) {
      for (var i = 0; i < 5; i++) {
        _h(top + i * s, left, right);
      }
    }
  }
}
