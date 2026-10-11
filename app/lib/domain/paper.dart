import 'dart:ui';

import 'templates/paper.dart';
import 'templates/paper_style.dart';

export 'templates/paper.dart';
export 'templates/paper_style.dart';
export 'templates/planner_calendar.dart';
export 'templates/planner_dates.dart';
export 'templates/planner_labels.dart';
export 'templates/planner_plan.dart';

/// The colour of the paper. Ink colours are unaffected, so dark paper is a
/// deliberate choice for light inks rather than a theme.
enum PaperColor {
  white(Color(0xFFFFFDF8), Color(0xFFD9DEE7), Color(0xFF5F6675)),
  cream(Color(0xFFF9F2E1), Color(0xFFE0D3B8), Color(0xFF6E5F45)),
  grey(Color(0xFFE8E9EC), Color(0xFFC7CBD3), Color(0xFF555B66)),
  dark(Color(0xFF202226), Color(0xFF3D4149), Color(0xFFA3A9B4));

  const PaperColor(this.paper, this.pattern, this.text);

  /// The sheet itself.
  final Color paper;

  /// Lines, dots and grids on this paper.
  final Color pattern;

  /// Printed text of templates (planner dates, headings).
  final Color text;

  bool get isDark => this == dark;

  String get label => '${name[0].toUpperCase()}${name.substring(1)}';

  static PaperColor parse(String? value) =>
      values.firstWhere((c) => c.name == value, orElse: () => white);
}

/// Standard page formats, in world units (96 units per inch).
enum PageFormat {
  a4('A4', 794, 1123),
  a5('A5', 559, 794),
  letter('Letter', 816, 1056),
  square('Square', 900, 900);

  const PageFormat(this.label, this.width, this.height);

  final String label;

  /// Portrait width and height.
  final double width;
  final double height;

  Size sizeFor(PageOrientation orientation) =>
      orientation == PageOrientation.portrait ? Size(width, height) : Size(height, width);

  /// The format and orientation of [size], or null for a custom size (e.g.
  /// an imported PDF page).
  static ({PageFormat format, PageOrientation orientation})? match(Size size) {
    for (final format in values) {
      for (final orientation in PageOrientation.values) {
        final s = format.sizeFor(orientation);
        if ((s.width - size.width).abs() < 1 && (s.height - size.height).abs() < 1) {
          return (format: format, orientation: orientation);
        }
      }
    }
    return null;
  }

  static PageFormat parse(String? value) =>
      values.firstWhere((f) => f.name == value, orElse: () => a4);
}

enum PageOrientation { portrait, landscape }

/// Everything needed to create a new blank page.
class PageTemplate {
  const PageTemplate({
    this.paper = Paper.blank,
    this.color = PaperColor.white,
    this.format = PageFormat.a4,
    this.orientation = PageOrientation.portrait,
    this.customSize,
  });

  /// A template of [style] without parameters (not planners or images).
  PageTemplate.of(PaperStyle style, {PaperColor color = PaperColor.white})
    : this(paper: Paper(style), color: color);

  final Paper paper;
  final PaperColor color;
  final PageFormat format;
  final PageOrientation orientation;

  /// A size of its own (a user's image template), overriding [format] and
  /// [orientation].
  final Size? customSize;

  PaperStyle get style => paper.style;

  Size get size => customSize ?? format.sizeFor(orientation);

  /// A copy with the given fields replaced. Choosing a [format] or
  /// [orientation] drops a [customSize]; pass [clearCustomSize] to drop it
  /// otherwise.
  PageTemplate copyWith({
    Paper? paper,
    PaperColor? color,
    PageFormat? format,
    PageOrientation? orientation,
    Size? customSize,
    bool clearCustomSize = false,
  }) => PageTemplate(
    paper: paper ?? this.paper,
    color: color ?? this.color,
    format: format ?? this.format,
    orientation: orientation ?? this.orientation,
    customSize: clearCustomSize || format != null || orientation != null
        ? customSize
        : customSize ?? this.customSize,
  );

  @override
  bool operator ==(Object other) =>
      other is PageTemplate &&
      other.paper == paper &&
      other.color == color &&
      other.format == format &&
      other.orientation == orientation &&
      other.customSize == customSize;

  @override
  int get hashCode => Object.hash(paper, color, format, orientation, customSize);
}
