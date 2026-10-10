/// Decorative pattern printed on a notebook cover.
enum CoverStyle {
  plain,
  linen,
  dots,
  grid,
  waves,
  stripes;

  /// Parses a stored name; unknown values (from newer app versions) fall
  /// back to [plain].
  static CoverStyle parse(String? value) =>
      values.firstWhere((s) => s.name == value, orElse: () => plain);
}
