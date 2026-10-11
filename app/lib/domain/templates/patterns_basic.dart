import 'dart:math' as math;
import 'dart:ui';

import '../paper_pattern.dart';
import 'pattern_builder.dart';

/// Repeating papers: ruled, grids, dots, isometric, music, graph and
/// engineering paper. All of them also tile an infinite canvas.
extension BasicPatterns on PatternBuilder {
  /// Header space above the first ruled line on a page.
  double get _top => (page?.top ?? 0) + 3 * s;

  /// Horizontal writing lines (below a header on pages) with a red margin.
  void ruled({double? bottom}) {
    final page = this.page;
    final start = page == null ? area.top : math.max(area.top, _top);
    if (shows(s)) {
      for (final y in ticks(start, bottom ?? area.bottom, s, page == null ? 0 : _top)) {
        h(y, area.left, area.right);
      }
    }
    if (page != null) v(page.left + 80, page.top, page.bottom, PatternWeight.margin);
  }

  void grid() => _grid(s, PatternWeight.normal);

  void _grid(double pitch, PatternWeight weight, {double origin = 0, double? top}) {
    if (!shows(pitch)) return;
    final y0 = top ?? area.top;
    for (final y in ticks(y0, area.bottom, pitch, top ?? origin)) {
      h(y, area.left, area.right, weight);
    }
    for (final x in ticks(area.left, area.right, pitch, origin)) {
      v(x, y0, area.bottom, weight);
    }
  }

  /// Grid lines every [pitch] that are not also lines of [coarser].
  void _subGrid(double pitch, int every, PatternWeight weight, {double origin = 0, double? top}) {
    if (!shows(pitch)) return;
    final y0 = top ?? area.top;
    bool onCoarse(double v, double o) => (((v - o) / pitch).round() % every) == 0;
    for (final y in ticks(y0, area.bottom, pitch, top ?? origin)) {
      if (!onCoarse(y, top ?? origin)) h(y, area.left, area.right, weight);
    }
    for (final x in ticks(area.left, area.right, pitch, origin)) {
      if (!onCoarse(x, origin)) v(x, y0, area.bottom, weight);
    }
  }

  void dotted() {
    if (!shows(s)) return;
    for (final y in ticks(area.top, area.bottom, s)) {
      for (final x in ticks(area.left, area.right, s)) {
        dots.add(Offset(x, y));
      }
    }
  }

  /// Millimetre paper: 1 cm lines heavy, 5 mm normal, 1 mm fine (each
  /// level shows once it is far enough apart on screen).
  void graph() {
    final cm = 2 * s, mm = s / 5;
    _subGrid(mm, 5, PatternWeight.fine);
    _subGrid(s, 2, PatternWeight.normal);
    // Centimetre lines stay visible longest.
    if (shows(cm)) _grid(cm, PatternWeight.heavy);
  }

  /// Engineering (quad) paper: five squares per inch, a bold line every
  /// inch; pages get a header strip above the grid.
  void engineering() {
    final page = this.page;
    final inch = 5 * s;
    final top = page == null ? null : page.top + 3 * s;
    if (page != null) {
      h(top!, page.left, page.right, PatternWeight.heavy);
      v(page.left + page.width * 0.7, page.top, top, PatternWeight.heavy);
    }
    final origin = page?.left ?? 0;
    _subGrid(s, 5, PatternWeight.normal, origin: origin, top: top);
    if (shows(inch)) _grid(inch, PatternWeight.heavy, origin: origin, top: top);
  }

  /// Lines at 0°, 60° and 120° forming equilateral triangles of side [s].
  void isometric() {
    if (!shows(s)) return;
    final hh = s * math.sqrt(3) / 2;
    for (final y in ticks(area.top, area.bottom, hh)) {
      h(y, area.left, area.right);
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
      for (final c in ticks(cs.reduce(math.min), cs.reduce(math.max), s)) {
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

  /// Five-line staves; [s] is the distance between staff lines.
  void music() {
    if (!shows(s)) return;
    final page = this.page;
    final period = 4 * s + 7 * s; // Staff height plus the gap to the next.
    final origin = page == null ? 0.0 : page.top + 6 * s;
    final left = page == null ? area.left : page.left + 48;
    final right = page == null ? area.right : page.right - 48;
    final end = page == null ? area.bottom : page.bottom - 4 * s;
    final from = page == null ? area.top - 4 * s : math.max(area.top - 4 * s, origin);
    for (final top in ticks(from, math.min(area.bottom, end - 4 * s), period, origin)) {
      for (var i = 0; i < 5; i++) {
        h(top + i * s, left, right);
      }
    }
  }
}
