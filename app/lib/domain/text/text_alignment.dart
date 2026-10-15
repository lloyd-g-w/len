/// Horizontal alignment of a text box, relative to each paragraph's
/// direction: [start] is the left edge of a left-to-right paragraph and the
/// right edge of a right-to-left one (Arabic, Hebrew). Stored by [name].
enum TextAlignment {
  start,
  center,
  end;

  /// The alignment named [value], or null.
  static TextAlignment? tryParse(Object? value) => values.asNameMap()[value];
}
