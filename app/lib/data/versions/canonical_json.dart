import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// JSON written the same, byte for byte, on every platform: object keys
/// sorted (by UTF-16 code units), no spaces, integral numbers without a
/// fraction (the web writes `1.0` as `1`, native code as `1.0`), other
/// numbers as their shortest round-trip form (alike on both), strings with
/// only `"`, `\`, control characters and lone surrogates escaped
/// (docs/SYNC_PROTOCOL.md, "Version history").
abstract final class CanonicalJson {
  /// [value] (maps, lists, strings, numbers, booleans, null) as canonical
  /// JSON. Throws [ArgumentError] for anything else, or non-finite numbers.
  static String encode(Object? value) {
    final out = StringBuffer();
    _write(out, value);
    return out.toString();
  }

  /// [value] as UTF-8 bytes of canonical JSON.
  static Uint8List bytes(Object? value) => utf8.encode(encode(value));

  static void _write(StringBuffer out, Object? value) {
    switch (value) {
      case null:
        out.write('null');
      case bool():
        out.write(value ? 'true' : 'false');
      case num():
        out.write(number(value));
      case String():
        _string(out, value);
      case List<Object?>():
        out.write('[');
        for (var i = 0; i < value.length; i++) {
          if (i > 0) out.write(',');
          _write(out, value[i]);
        }
        out.write(']');
      case Map<Object?, Object?>():
        final keys = [for (final k in value.keys) k as String]..sort();
        out.write('{');
        for (var i = 0; i < keys.length; i++) {
          if (i > 0) out.write(',');
          _string(out, keys[i]);
          out.write(':');
          _write(out, value[keys[i]]);
        }
        out.write('}');
      default:
        throw ArgumentError.value(value, 'value', 'not JSON');
    }
  }

  /// [n] as canonical JSON.
  static String number(num n) {
    if (!n.isFinite) throw ArgumentError.value(n, 'n', 'not finite');
    if (n is int) return n.toString();
    // Integral doubles within the exact range print as integers (as the web
    // does); others print alike on both (shortest round-trip, exponent
    // beyond 1e21 and below 1e-6).
    if (n == n.truncateToDouble() && n.abs() < _exact) return n.toInt().toString();
    return n.toString();
  }

  static const _exact = 9007199254740992.0; // 2^53

  static void _string(StringBuffer out, String s) {
    out.write('"');
    var start = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      String? escape;
      if (c == 0x22) {
        escape = r'\"';
      } else if (c == 0x5c) {
        escape = r'\\';
      } else if (c < 0x20) {
        escape = switch (c) {
          0x0a => r'\n',
          0x0d => r'\r',
          0x09 => r'\t',
          _ => _unicode(c),
        };
      } else if (c >= 0xd800 && c <= 0xdfff) {
        final high = c < 0xdc00;
        final paired = high
            ? i + 1 < s.length && (s.codeUnitAt(i + 1) & 0xfc00) == 0xdc00
            : i > 0 && (s.codeUnitAt(i - 1) & 0xfc00) == 0xd800;
        if (!paired) escape = _unicode(c);
      }
      if (escape == null) continue;
      out
        ..write(s.substring(start, i))
        ..write(escape);
      start = i + 1;
    }
    out
      ..write(s.substring(start))
      ..write('"');
  }

  static String _unicode(int c) => '\\u${c.toRadixString(16).padLeft(4, '0')}';
}

/// Blobs of canonical JSON compressed with deflate (zlib), behind a magic
/// of two bytes and a format byte. Compressed by the same pure-Dart
/// encoder on every platform (the native one compresses differently), so
/// equal content makes equal bytes, and so the same blob, everywhere.
abstract final class DeflatedJson {
  /// The bytes of [value] behind [magic] (two bytes) and [format].
  static Uint8List encode(List<int> magic, int format, Object? value) {
    final packed = const ZLibEncoderWeb().encodeBytes(CanonicalJson.bytes(value), level: 6);
    return Uint8List(3 + packed.length)
      ..setAll(0, magic)
      ..[2] = format
      ..setAll(3, packed);
  }

  /// Whether [bytes] begin with [magic] and [format].
  static bool isOf(List<int> bytes, List<int> magic, int format) =>
      bytes.length > 3 && bytes[0] == magic[0] && bytes[1] == magic[1] && bytes[2] == format;

  /// The JSON value in [bytes] (see [isOf]); null when they hold none.
  static Object? decode(Uint8List bytes) {
    try {
      final json = const ZLibDecoder().decodeBytes(Uint8List.sublistView(bytes, 3), verify: true);
      return jsonDecode(utf8.decode(json));
    } on Object {
      return null; // Corrupt: no valid stream, or no JSON.
    }
  }
}
