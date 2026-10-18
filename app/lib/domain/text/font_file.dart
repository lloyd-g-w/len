import 'dart:convert';
import 'dart:typed_data';

/// How a font file draws its glyphs.
enum FontOutlines {
  /// TrueType quadratic outlines (`glyf`): what PDF export can embed.
  trueType,

  /// PostScript (CFF) outlines, as in most `.otf` files: drawn on screen,
  /// exported to PDF as images.
  cff,
}

/// What Len reads from a TTF / OTF file before importing it: its names
/// (the `name` table) and outline format. Pure Dart, no rendering.
class FontFileInfo {
  const FontFileInfo({required this.family, required this.style, required this.outlines});

  /// The (typographic) family name, e.g. "Source Serif 4".
  final String family;

  /// The style within the family, e.g. "Regular", "Bold Italic".
  final String style;

  final FontOutlines outlines;

  /// The name shown in the font picker: the family, with its style unless
  /// that is the regular one.
  String get displayName {
    final s = style.trim();
    if (s.isEmpty || const {'regular', 'normal', 'book', 'roman'}.contains(s.toLowerCase())) {
      return family;
    }
    return '$family $s';
  }

  /// The info of the font file [bytes]; null if it is not a single
  /// TrueType / OpenType font with the tables text needs (collections,
  /// WOFF and other files are refused).
  static FontFileInfo? read(Uint8List bytes) {
    try {
      return _read(ByteData.sublistView(bytes));
    } on RangeError {
      return null;
    }
  }

  static FontFileInfo? _read(ByteData b) {
    final tag = b.getUint32(0);
    final FontOutlines outlines;
    if (tag == 0x00010000 || tag == 0x74727565 /* true */ ) {
      outlines = FontOutlines.trueType;
    } else if (tag == 0x4F54544F /* OTTO */ ) {
      outlines = FontOutlines.cff;
    } else {
      return null;
    }
    final tables = <String, ({int offset, int length})>{};
    final count = b.getUint16(4);
    for (var i = 0; i < count; i++) {
      final at = 12 + i * 16;
      final name = String.fromCharCodes([for (var k = 0; k < 4; k++) b.getUint8(at + k)]);
      tables[name] = (offset: b.getUint32(at + 8), length: b.getUint32(at + 12));
    }
    const needed = ['cmap', 'head', 'hhea', 'hmtx', 'maxp', 'name'];
    if (!needed.every(tables.containsKey)) return null;
    if (outlines == FontOutlines.trueType && !tables.containsKey('glyf')) return null;
    if (outlines == FontOutlines.cff &&
        !tables.containsKey('CFF ') &&
        !tables.containsKey('CFF2')) {
      return null;
    }
    final names = _names(b, tables['name']!.offset);
    final family = names[16] ?? names[1];
    if (family == null || family.trim().isEmpty) return null;
    return FontFileInfo(
      family: family.trim(),
      style: (names[17] ?? names[2] ?? '').trim(),
      outlines: outlines,
    );
  }

  /// The `name` table's strings by name id, preferring Windows (English)
  /// and Unicode records over Mac ones.
  static Map<int, String> _names(ByteData b, int table) {
    final count = b.getUint16(table + 2);
    final strings = table + b.getUint16(table + 4);
    final found = <int, (int rank, String text)>{};
    for (var i = 0; i < count; i++) {
      final at = table + 6 + i * 12;
      final platform = b.getUint16(at), encoding = b.getUint16(at + 2);
      final language = b.getUint16(at + 4), id = b.getUint16(at + 6);
      final length = b.getUint16(at + 8), offset = strings + b.getUint16(at + 10);
      final int rank;
      final String text;
      if (platform == 3 && (encoding == 1 || encoding == 10)) {
        rank = language == 0x409 ? 0 : 1;
        text = _utf16(b, offset, length);
      } else if (platform == 0) {
        rank = 2;
        text = _utf16(b, offset, length);
      } else if (platform == 1 && encoding == 0) {
        rank = language == 0 ? 3 : 4;
        text = latin1.decode(Uint8List.sublistView(b, offset, offset + length));
      } else {
        continue;
      }
      final best = found[id];
      if (best == null || rank < best.$1) found[id] = (rank, text);
    }
    return {for (final MapEntry(:key, :value) in found.entries) key: value.$2};
  }

  static String _utf16(ByteData b, int offset, int length) =>
      String.fromCharCodes([for (var i = 0; i + 1 < length; i += 2) b.getUint16(offset + i)]);
}
