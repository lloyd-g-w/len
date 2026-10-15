/// Horizontal alignment of a text box. Stored by [name].
enum TextAlignment {
  left,
  center,
  right;

  static TextAlignment parse(Object? value) =>
      values.firstWhere((a) => a.name == value, orElse: () => left);
}
