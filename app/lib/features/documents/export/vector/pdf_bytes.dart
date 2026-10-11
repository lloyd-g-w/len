/// Byte-level helpers shared by the PDF lexer and reader.
library;

import 'dart:typed_data';

/// Whether [c] is a PDF whitespace byte.
bool isPdfWhite(int c) => c == 0x20 || c == 0x0a || c == 0x0d || c == 0x09 || c == 0x0c || c == 0;

/// Whether [c] is a PDF delimiter byte: `( ) < > [ ] { } / %`.
bool isPdfDelimiter(int c) =>
    c == 0x28 ||
    c == 0x29 ||
    c == 0x3c ||
    c == 0x3e ||
    c == 0x5b ||
    c == 0x5d ||
    c == 0x7b ||
    c == 0x7d ||
    c == 0x2f ||
    c == 0x25;

/// The index of the first occurrence of [pattern] in [bytes] at or after
/// [start] (and before [end]), or -1.
int indexOfBytes(Uint8List bytes, List<int> pattern, [int start = 0, int? end]) {
  final last = (end ?? bytes.length) - pattern.length;
  outer:
  for (var i = start < 0 ? 0 : start; i <= last; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// The index of the last occurrence of [pattern] in [bytes], or -1.
int lastIndexOfBytes(Uint8List bytes, List<int> pattern) {
  outer:
  for (var i = bytes.length - pattern.length; i >= 0; i--) {
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// The value of hex digit [c], or -1.
int hexDigitValue(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  return -1;
}
