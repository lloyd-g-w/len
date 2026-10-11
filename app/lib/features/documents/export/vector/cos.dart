/// The PDF object model ("COS" objects) read from a source PDF.
///
/// Pure Dart (no `dart:io`), so it works on every platform including the web.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Thrown when a PDF cannot be read, or a page cannot be copied faithfully.
class PdfReadException implements Exception {
  /// Creates an exception with a human-readable [message].
  PdfReadException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'PdfReadException: $message';
}

/// Base class of every PDF object.
sealed class CosObject {
  const CosObject();
}

/// The `null` object.
final class CosNull extends CosObject {
  /// The single null instance.
  static const instance = CosNull._();

  const CosNull._();

  @override
  String toString() => 'null';
}

/// A boolean.
final class CosBool extends CosObject {
  /// Creates a boolean object.
  const CosBool(this.value);

  /// The value.
  final bool value;

  @override
  String toString() => '$value';
}

/// An integer or real number.
final class CosNumber extends CosObject {
  /// Creates a number object.
  const CosNumber(this.value);

  /// The value; an [int] for integer tokens, a [double] for reals.
  final num value;

  @override
  String toString() => '$value';
}

/// A string (literal or hexadecimal), kept as raw bytes.
final class CosString extends CosObject {
  /// Creates a string object.
  const CosString(this.bytes, {this.hex = false});

  /// The decoded bytes.
  final Uint8List bytes;

  /// Whether the source used the `<…>` hexadecimal syntax.
  final bool hex;

  /// The bytes interpreted as Latin-1 (good enough for diagnostics and ASCII).
  String get text => latin1.decode(bytes);

  @override
  String toString() => '($text)';
}

/// A name, without its leading `/` and with `#xx` escapes decoded.
///
/// Characters are bytes (code units 0–255).
final class CosName extends CosObject {
  /// Creates a name object.
  const CosName(this.name);

  /// The name without the leading slash.
  final String name;

  @override
  bool operator ==(Object other) => other is CosName && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => '/$name';
}

/// An array.
final class CosArray extends CosObject {
  /// Creates an array object.
  CosArray(this.items);

  /// The elements.
  final List<CosObject> items;

  @override
  String toString() => '$items';
}

/// A dictionary, keyed by name (without the leading slash).
final class CosDict extends CosObject {
  /// Creates a dictionary object.
  CosDict([Map<String, CosObject>? entries]) : entries = entries ?? {};

  /// The entries, in source order.
  final Map<String, CosObject> entries;

  /// The (unresolved) value for [key], or null.
  CosObject? operator [](String key) => entries[key];

  @override
  String toString() => '<<${entries.entries.map((e) => '/${e.key} ${e.value}').join(' ')}>>';
}

/// A stream: its dictionary plus the raw (still encoded) bytes.
final class CosStream extends CosObject {
  /// Creates a stream object.
  CosStream(this.dict, this.raw);

  /// The stream dictionary.
  final CosDict dict;

  /// The raw bytes between `stream` and `endstream`, still filtered.
  final Uint8List raw;

  @override
  String toString() => '$dict stream[${raw.length}]';
}

/// An indirect reference `n g R`.
final class CosRef extends CosObject {
  /// Creates a reference.
  const CosRef(this.number, this.gen);

  /// The object number.
  final int number;

  /// The generation number.
  final int gen;

  @override
  bool operator ==(Object other) => other is CosRef && other.number == number && other.gen == gen;

  @override
  int get hashCode => Object.hash(number, gen);

  @override
  String toString() => '$number $gen R';
}

/// Convenience accessors on possibly-null objects.
extension CosObjectX on CosObject? {
  /// The number value, or null.
  num? get asNum => switch (this) {
    CosNumber(:final value) => value,
    _ => null,
  };

  /// The integer value (reals truncated), or null.
  int? get asInt => asNum?.toInt();

  /// The name (without slash), or null.
  String? get asName => switch (this) {
    CosName(:final name) => name,
    _ => null,
  };
}
