/// The font families bundled for text boxes (`assets/fonts`, SIL Open Font
/// License 1.1). Stored by [name] in `TextData` / `SpanStyle`; never
/// rename a value. Unknown names fall back to [inter].
///
/// Text boxes only use bundled fonts, so they look, measure and wrap the
/// same on every platform and in exported PDFs.
enum TextFont {
  /// Inter: the default sans serif.
  inter('Inter', 'Sans'),

  /// Nunito: a friendly rounded sans serif.
  nunito('Nunito', 'Rounded'),

  /// Lora: a calm book serif.
  lora('Lora', 'Serif'),

  /// JetBrains Mono: monospaced, for code and tables.
  mono('JetBrains Mono', 'Mono'),

  /// Caveat: handwriting style (no italic: Flutter and the PDF export
  /// slant it).
  caveat('Caveat', 'Handwriting'),

  /// Kalam: neat hand lettering (no italic, slanted like [caveat]).
  kalam('Kalam', 'Hand lettering');

  const TextFont(this.family, this.label);

  /// The family name declared in `pubspec.yaml`.
  final String family;

  /// Name shown in the font picker.
  final String label;

  /// Whether the font has real italic faces (otherwise italic is slanted).
  bool get hasItalic => this != caveat && this != kalam;

  /// The asset file of one face, e.g. `assets/fonts/Inter-BoldItalic.ttf`.
  String asset({bool bold = false, bool italic = false}) {
    final file = switch (this) {
      inter => 'Inter',
      lora => 'Lora',
      mono => 'JetBrainsMono',
      caveat => 'Caveat',
      nunito => 'Nunito',
      kalam => 'Kalam',
    };
    final i = italic && hasItalic;
    final face = bold ? (i ? 'BoldItalic' : 'Bold') : (i ? 'Italic' : 'Regular');
    return 'assets/fonts/$file-$face.ttf';
  }

  /// The font's licence (SIL Open Font License 1.1) next to its files.
  String get licenseAsset => asset().replaceFirst('-Regular.ttf', '-OFL.txt');

  static TextFont parse(Object? value) =>
      values.firstWhere((f) => f.name == value, orElse: () => inter);

  /// [value] as a font, or null if it names none.
  static TextFont? tryParse(Object? value) {
    for (final f in values) {
      if (f.name == value) return f;
    }
    return null;
  }
}
