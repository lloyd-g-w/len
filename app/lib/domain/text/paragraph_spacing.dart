/// Space a text box leaves between its paragraphs (below each one but the
/// last), as a fraction of the box's font size, so it scales with the
/// box. Stored by [name] as the text data's `spacing` (left out for
/// [none]).
enum ParagraphSpacing {
  none(0, 'None'),
  small(0.25, 'Small'),
  medium(0.5, 'Medium'),
  large(1, 'Large');

  const ParagraphSpacing(this.factor, this.label);

  /// The space, in multiples of the box's font size.
  final double factor;

  /// The name shown in menus.
  final String label;

  /// The spacing named [value], or null.
  static ParagraphSpacing? tryParse(Object? value) => values.asNameMap()[value];

  /// The spacing nearest to [em] multiples of the font size.
  static ParagraphSpacing nearest(double em) {
    var best = none;
    for (final s in values) {
      if ((s.factor - em).abs() < (best.factor - em).abs()) best = s;
    }
    return best;
  }
}
