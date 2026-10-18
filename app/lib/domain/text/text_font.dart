import 'package:flutter/foundation.dart' show immutable;

/// A text-box font: one of the families bundled with the app
/// (`assets/fonts`, SIL Open Font License 1.1) or one the user imported
/// (a TTF / OTF file synced as a blob, see `UserFont`). Stored by [name]:
/// a bundled font's name (never rename one), or a user font's id (32
/// lowercase hex digits, [isUserId]). Unknown names fall back to [inter].
///
/// Bundled fonts look, measure and wrap the same on every platform and in
/// exported PDFs; a user font does wherever it has been loaded (until then,
/// or once removed, its text is shown in [inter]).
@immutable
final class TextFont {
  const TextFont._(this.name, this.family, this._label, this._file);

  /// The imported font with id [id] ([isUserId]).
  TextFont.user(String id)
    : assert(isUserId(id), 'Not a user font id: $id'),
      name = id,
      family = 'Len font $id',
      _label = null,
      _file = null;

  /// Inter: the default sans serif.
  static const inter = TextFont._('inter', 'Inter', 'Sans', 'Inter');

  /// Lora: a calm book serif.
  static const lora = TextFont._('lora', 'Lora', 'Serif', 'Lora');

  /// JetBrains Mono: monospaced, for code and tables.
  static const mono = TextFont._('mono', 'JetBrains Mono', 'Mono', 'JetBrainsMono');

  /// Caveat: handwriting style (no italic: Flutter and the PDF export
  /// slant it).
  static const caveat = TextFont._('caveat', 'Caveat', 'Handwriting', 'Caveat');

  /// The bundled fonts, in the font picker's order.
  static const bundled = [inter, lora, mono, caveat];

  /// What is stored: a bundled font's name or a user font's id.
  final String name;

  /// The family name: declared in `pubspec.yaml` for bundled fonts, the
  /// one a user font is loaded as (see `TextFonts`).
  final String family;

  final String? _label;

  /// Asset file stem of a bundled font; null for user fonts.
  final String? _file;

  /// Whether the user imported this font.
  bool get isUser => _file == null;

  /// Name shown in the font picker (bundled fonts; a user font's name is
  /// in its record).
  String get label => _label ?? 'Imported font';

  /// Whether the font has real italic faces (otherwise italic is slanted;
  /// user fonts are one face each).
  bool get hasItalic => !isUser && this != caveat;

  /// Whether [value] is a user font id: 32 lowercase hex digits (the first
  /// half of the font file's SHA-256, so the same file has the same id on
  /// every device).
  static bool isUserId(Object? value) => value is String && _userId.hasMatch(value);

  static final _userId = RegExp(r'^[0-9a-f]{32}$');

  /// The user font id of the font file whose SHA-256 is [sha].
  static String userIdOf(String sha) => sha.substring(0, 32);

  /// The asset file of one face of a bundled font, e.g.
  /// `assets/fonts/Inter-BoldItalic.ttf`.
  String asset({bool bold = false, bool italic = false}) {
    final file = _file;
    if (file == null) throw StateError('A user font has no asset');
    final i = italic && hasItalic;
    final face = bold ? (i ? 'BoldItalic' : 'Bold') : (i ? 'Italic' : 'Regular');
    return 'assets/fonts/$file-$face.ttf';
  }

  /// A bundled font's licence (SIL Open Font License 1.1) next to its files.
  String get licenseAsset => asset().replaceFirst('-Regular.ttf', '-OFL.txt');

  static TextFont parse(Object? value) => tryParse(value) ?? inter;

  /// [value] as a font, or null if it names none.
  static TextFont? tryParse(Object? value) {
    for (final f in bundled) {
      if (f.name == value) return f;
    }
    return isUserId(value) ? TextFont.user(value! as String) : null;
  }

  @override
  bool operator ==(Object other) => other is TextFont && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'TextFont($name)';
}

/// Bundled fallbacks of the text-box fonts for scripts they lack (Noto
/// Sans, SIL Open Font License 1.1, Regular and Bold): Arabic and Hebrew
/// render the same on every platform, the web included, and in exported
/// PDFs. Never stored.
enum FallbackFont {
  arabic('Noto Sans Arabic', 'NotoSansArabic'),
  hebrew('Noto Sans Hebrew', 'NotoSansHebrew');

  const FallbackFont(this.family, this._file);

  /// The family name declared in `pubspec.yaml`.
  final String family;
  final String _file;

  /// The asset file of the Regular or [bold] face.
  String asset({bool bold = false}) => 'assets/fonts/$_file-${bold ? 'Bold' : 'Regular'}.ttf';

  /// The font's licence (SIL Open Font License 1.1) next to its files.
  String get licenseAsset => 'assets/fonts/$_file-OFL.txt';
}
