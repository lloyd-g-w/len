import 'dart:ui';

import 'templates/paper.dart';
import 'templates/paper_style.dart';
import 'templates/pattern_builder.dart';
import 'templates/patterns_basic.dart';
import 'templates/patterns_planner.dart';
import 'templates/patterns_writing.dart';

/// How prominent a pattern line is.
enum PatternWeight {
  /// Sub-divisions that only show when zoomed in (1 mm graph lines).
  fine,

  /// Ordinary ruling, grid and staff lines.
  normal,

  /// Structural lines (Cornell sections, planner frames, checkboxes).
  heavy,

  /// The red margin line of ruled paper.
  margin,
}

/// One straight pattern line in world coordinates.
typedef PatternLine = ({Offset a, Offset b, PatternWeight weight});

/// Horizontal placement of a label within its box.
enum LabelAlign { start, center, end }

/// Printed text of a template (planner dates, section headings), vertically
/// centred in [box] (world units), [size] units high.
class PatternLabel {
  const PatternLabel(
    this.text,
    this.box, {
    required this.size,
    this.align = LabelAlign.start,
    this.bold = false,
    this.muted = false,
  });

  final String text;
  final Rect box;
  final double size;
  final LabelAlign align;
  final bool bold;

  /// Secondary text (drawn lighter).
  final bool muted;

  @override
  String toString() => 'PatternLabel($text, $box)';
}

/// A tinted area (planner header bands, days outside the month), drawn in
/// the pattern colour at [opacity].
typedef PatternFill = ({Rect rect, double opacity});

/// A tappable area of a planner page leading to the page of [target] in
/// the same notebook.
typedef PatternLink = ({Rect rect, Paper target});

/// The geometry of a paper template within an area, independent of how it
/// is drawn (on screen, in thumbnails, or into an exported PDF).
class PaperPattern {
  const PaperPattern({
    this.lines = const [],
    this.dots = const [],
    this.labels = const [],
    this.fills = const [],
    this.links = const [],
  });

  final List<PatternLine> lines;
  final List<Offset> dots;
  final List<PatternLabel> labels;
  final List<PatternFill> fills;

  /// Planner navigation; covers the whole page whatever the area.
  final List<PatternLink> links;

  bool get isEmpty => lines.isEmpty && dots.isEmpty && labels.isEmpty && fills.isEmpty;

  /// Pattern pieces of [paper] intersecting [area] (world coordinates).
  ///
  /// [page] is the page rectangle (pages have margins and sections), or
  /// null for an infinite canvas, where the pattern tiles forever.
  /// Repeating detail closer than [minPitch] world units (too dense to see
  /// at the current zoom) is left out; structure (sections, frames,
  /// labels) stays.
  static PaperPattern of(Paper paper, Rect area, {Rect? page, double minPitch = 0}) {
    final region = page == null ? area : area.intersect(page);
    final style = paper.style;
    if (region.isEmpty || style == PaperStyle.blank || style == PaperStyle.image) {
      return const PaperPattern();
    }
    final b = PatternBuilder(style.spacing, region, page, minPitch: minPitch);
    if (page == null && !style.canvas) {
      b.ruled(); // Page layouts have no meaning on a canvas.
    } else {
      _build(b, paper, page);
    }
    return PaperPattern(
      lines: b.lines,
      dots: b.dots,
      labels: b.labels,
      fills: b.fills,
      links: b.links,
    );
  }

  static void _build(PatternBuilder b, Paper paper, Rect? page) {
    switch (paper.style) {
      case PaperStyle.blank || PaperStyle.image:
        break;
      case PaperStyle.wideRuled || PaperStyle.collegeRuled || PaperStyle.narrowRuled:
        b.ruled();
      case PaperStyle.gridLarge || PaperStyle.gridSmall:
        b.grid();
      case PaperStyle.dotted:
        b.dotted();
      case PaperStyle.isometric:
        b.isometric();
      case PaperStyle.music:
        b.music();
      case PaperStyle.graph:
        b.graph();
      case PaperStyle.engineering:
        b.engineering();
      case PaperStyle.cornell:
        b.cornell(page!);
      case PaperStyle.todo:
        b.todo(page!);
      case PaperStyle.meeting:
        b.meeting(page!);
      case PaperStyle.storyboard:
        b.storyboard(page!);
      case PaperStyle.dailyPlanner:
        b.daily(page!, paper.date);
      case PaperStyle.weeklyPlanner:
        b.weekly(page!, paper.date);
      case PaperStyle.monthlyCalendar:
        b.monthly(page!, paper.date);
    }
  }
}
