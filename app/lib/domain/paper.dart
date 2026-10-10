/// Background pattern drawn behind ink.
enum PaperStyle {
  blank,
  lined,
  grid,
  dotted;

  static PaperStyle parse(String value) =>
      values.firstWhere((p) => p.name == value, orElse: () => blank);
}

/// Default page dimensions in world units (A4 at 96 dpi).
abstract final class PageSize {
  static const double a4Width = 794;
  static const double a4Height = 1123;
}
