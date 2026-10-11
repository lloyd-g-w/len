import 'dart:ui';

/// Background pattern ("template") drawn behind ink.
///
/// Stored and synced by [name].
enum PaperStyle {
  blank('Blank', 0),

  /// Wide ruled (8.5 mm).
  wideRuled('Wide ruled', 32),

  /// Large grid (8.5 mm).
  gridLarge('Large grid', 32),
  dotted('Dotted', 32),
  collegeRuled('College ruled', 27),
  narrowRuled('Narrow ruled', 24),
  gridSmall('Small grid', 19),
  cornell('Cornell notes', 27),
  music('Music staff', 9),
  isometric('Isometric', 32);

  const PaperStyle(this.label, this.spacing);

  /// Human-readable name for pickers.
  final String label;

  /// Pattern pitch in world units (line distance, grid cell, dot spacing,
  /// or staff line distance for [music]). Zero for [blank].
  final double spacing;

  /// The order in which templates are offered to the user.
  static const List<PaperStyle> ordered = [
    blank,
    narrowRuled,
    collegeRuled,
    wideRuled,
    gridSmall,
    gridLarge,
    dotted,
    isometric,
    cornell,
    music,
  ];

  /// Whether the pattern consists of horizontal writing lines.
  bool get isRuled => this == wideRuled || this == collegeRuled || this == narrowRuled;

  /// Parses a stored name; an unknown one (corrupt data) reads as [blank].
  static PaperStyle parse(String value) =>
      values.firstWhere((p) => p.name == value, orElse: () => blank);
}

/// The colour of the paper. Ink colours are unaffected, so dark paper is a
/// deliberate choice for light inks rather than a theme.
enum PaperColor {
  white(Color(0xFFFFFDF8), Color(0xFFD9DEE7)),
  cream(Color(0xFFF9F2E1), Color(0xFFE0D3B8)),
  grey(Color(0xFFE8E9EC), Color(0xFFC7CBD3)),
  dark(Color(0xFF202226), Color(0xFF3D4149));

  const PaperColor(this.paper, this.pattern);

  /// The sheet itself.
  final Color paper;

  /// Lines, dots and grids on this paper.
  final Color pattern;

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
    this.style = PaperStyle.blank,
    this.color = PaperColor.white,
    this.format = PageFormat.a4,
    this.orientation = PageOrientation.portrait,
  });

  final PaperStyle style;
  final PaperColor color;
  final PageFormat format;
  final PageOrientation orientation;

  Size get size => format.sizeFor(orientation);

  PageTemplate copyWith({
    PaperStyle? style,
    PaperColor? color,
    PageFormat? format,
    PageOrientation? orientation,
  }) => PageTemplate(
    style: style ?? this.style,
    color: color ?? this.color,
    format: format ?? this.format,
    orientation: orientation ?? this.orientation,
  );

  @override
  bool operator ==(Object other) =>
      other is PageTemplate &&
      other.style == style &&
      other.color == color &&
      other.format == format &&
      other.orientation == orientation;

  @override
  int get hashCode => Object.hash(style, color, format, orientation);
}

/// Default page dimensions in world units (A4 at 96 dpi).
abstract final class PageSize {
  static const double a4Width = 794;
  static const double a4Height = 1123;
}
