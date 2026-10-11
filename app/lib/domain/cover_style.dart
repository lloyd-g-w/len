/// Decorative pattern printed on a notebook cover.
enum CoverStyle {
  plain,
  linen,
  dots,
  grid,
  waves,
  stripes;

  /// Parses a stored name; an unknown one (corrupt data) reads as [plain].
  static CoverStyle parse(String? value) =>
      values.firstWhere((s) => s.name == value, orElse: () => plain);
}
