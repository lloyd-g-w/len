import 'dart:math' as math;
import 'dart:ui';

import '../paper_pattern.dart';
import 'paper.dart';

/// Collects the pieces of a template within [area]: lines clipped to it,
/// and labels and fills that touch it. Template layouts are written as
/// extensions on this class (`patterns_*.dart`).
class PatternBuilder {
  PatternBuilder(
    this.s,
    this.area,
    this.page, {
    this.minPitch = 0,
    this.headerBottom,
    this.margin = true,
  });

  /// The template's pitch (`Paper.pitch`).
  final double s;
  final Rect area;

  /// The page, or null on an infinite canvas.
  final Rect? page;

  /// Repeating detail closer than this is left out (too dense to see).
  final double minPitch;

  /// Where a page's header area ends (the pattern starts there), if it has one.
  final double? headerBottom;

  /// Whether ruled pages get their margin line.
  final bool margin;

  /// Height of a page's header area.
  static double headerHeight(Rect page) => math.max(56, page.height * 0.09);

  final List<PatternLine> lines = [];
  final List<Offset> dots = [];
  final List<PatternLabel> labels = [];
  final List<PatternFill> fills = [];
  final List<PatternLink> links = [];

  /// Whether repetitions [pitch] apart are worth drawing.
  bool shows(double pitch) => pitch >= minPitch;

  /// A horizontal line at [y] from [x0] to [x1], clipped to the area.
  void h(double y, double x0, double x1, [PatternWeight w = PatternWeight.normal]) {
    final from = math.max(x0, area.left), to = math.min(x1, area.right);
    if (y < area.top || y > area.bottom || from >= to) return;
    lines.add((a: Offset(from, y), b: Offset(to, y), weight: w));
  }

  /// A vertical line at [x] from [y0] to [y1], clipped to the area.
  void v(double x, double y0, double y1, [PatternWeight w = PatternWeight.normal]) {
    final from = math.max(y0, area.top), to = math.min(y1, area.bottom);
    if (x < area.left || x > area.right || from >= to) return;
    lines.add((a: Offset(x, from), b: Offset(x, to), weight: w));
  }

  /// The outline of [r].
  void box(Rect r, [PatternWeight w = PatternWeight.heavy]) {
    h(r.top, r.left, r.right, w);
    h(r.bottom, r.left, r.right, w);
    v(r.left, r.top, r.bottom, w);
    v(r.right, r.top, r.bottom, w);
  }

  /// A checkbox of side [side] whose left edge is at [x], centred on a
  /// writing line at [y] (sitting just above it).
  void checkbox(double x, double y, double side) =>
      box(Rect.fromLTWH(x, y - side - side * 0.35, side, side));

  /// Writing lines [pitch] apart from [top] (inclusive) to [bottom], between
  /// [x0] and [x1]. Returns the y of each line (also when hidden as too
  /// dense), so callers can decorate them.
  List<double> rules(double top, double bottom, double x0, double x1, {double? pitch}) {
    final p = pitch ?? s;
    final ys = [for (var y = top; y <= bottom + 1e-6; y += p) y];
    if (shows(p)) {
      for (final y in ys) {
        h(y, x0, x1);
      }
    }
    return ys;
  }

  /// A label in [box] if it touches the area.
  void label(
    String text,
    Rect box, {
    required double size,
    LabelAlign align = LabelAlign.start,
    bool bold = false,
    bool muted = false,
  }) {
    if (!box.overlaps(area)) return;
    labels.add(PatternLabel(text, box, size: size, align: align, bold: bold, muted: muted));
  }

  /// A small capitalised heading with its baseline region ending at [y].
  void heading(String text, double x, double y, {double width = 300}) =>
      label(text.toUpperCase(), Rect.fromLTWH(x, y - 18, width, 16), size: 10.5, bold: true);

  /// A tint over [r] (clipped to the area).
  void fill(Rect r, double opacity) {
    final clipped = r.intersect(area);
    if (clipped.isEmpty) return;
    fills.add((rect: clipped, opacity: opacity));
  }

  /// A link from [r] to the page of [target].
  void link(Rect r, Paper target) => links.add((rect: r, target: target));

  /// Multiples of [step] (offset by [origin]) within [from, to].
  Iterable<double> ticks(double from, double to, double step, [double origin = 0]) sync* {
    for (var v = ((from - origin) / step).ceil() * step + origin; v <= to; v += step) {
      yield v;
    }
  }

  /// The page's content rectangle: the page inset by a margin that scales
  /// with its size.
  Rect content(Rect page) {
    final m = math.max(28.0, math.min(page.width, page.height) * 0.06);
    return page.deflate(m);
  }
}
