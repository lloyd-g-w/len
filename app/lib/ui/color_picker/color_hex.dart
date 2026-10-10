/// Hex formatting and parsing of ARGB colours (CSS order: `RRGGBB[AA]`).
abstract final class ColorHex {
  /// `RRGGBB` in upper case (alpha omitted).
  static String rgb(int argb) => (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  /// Parses `RGB`, `RRGGBB` or `RRGGBBAA`, with or without a leading `#`.
  /// Without an alpha part the result takes [alpha] (0..255). Returns null
  /// for anything else.
  static int? parse(String input, {int alpha = 0xFF}) {
    var hex = input.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;
    switch (hex.length) {
      case 3:
        hex = hex.split('').map((c) => '$c$c').join();
        return (alpha.clamp(0, 255) << 24) | int.parse(hex, radix: 16);
      case 6:
        return (alpha.clamp(0, 255) << 24) | int.parse(hex, radix: 16);
      case 8:
        final rgb = int.parse(hex.substring(0, 6), radix: 16);
        final a = int.parse(hex.substring(6), radix: 16);
        return (a << 24) | rgb;
      default:
        return null;
    }
  }
}
