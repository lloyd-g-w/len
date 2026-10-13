import 'dart:convert';

import 'stroke.dart';
import 'surface_element.dart';

/// What a chunk of a surface holds, in a few numbers: how many strokes and
/// elements are indexed in it and the sums of their [item] hashes.
///
/// Sums can be kept by storage without reading anything back (each
/// `stroke_chunks` / `element_chunks` row carries its item's hash, and
/// SQLite adds them up per chunk) and computed from the items in memory
/// alike, so a cached rendering of a chunk can be looked up by its digest
/// without loading the chunk: same digest, same content. Strokes are
/// immutable, so a stroke's id stands for its content; an element keeps
/// its id when edited, so it hashes its whole value instead (not its id:
/// a copy on another surface hashes the same).
class ChunkDigest {
  const ChunkDigest({this.strokes = 0, this.strokeSum = 0, this.elements = 0, this.elementSum = 0});

  final int strokes;
  final int strokeSum;
  final int elements;
  final int elementSum;

  /// The digest of [strokes] and [elements] (those indexed in one chunk).
  factory ChunkDigest.of(Iterable<Stroke> strokes, Iterable<SurfaceElement> elements) {
    var n = 0, sum = 0, m = 0, elementSum = 0;
    for (final s in strokes) {
      n++;
      sum += ofStroke(s.id);
    }
    for (final e in elements) {
      m++;
      elementSum += ofElement(e);
    }
    return ChunkDigest(strokes: n, strokeSum: sum, elements: m, elementSum: elementSum);
  }

  /// The hash of stroke [id] (48 bits: sums of 32 768 fit SQLite's integers).
  static int ofStroke(String id) => _hash48(id);

  /// The hash of [e]'s value (everything that is drawn; not its id).
  static int ofElement(SurfaceElement e) => _hash48(
    jsonEncode([
      e.type,
      e.rect.left,
      e.rect.top,
      e.rect.width,
      e.rect.height,
      e.rotation,
      e.z,
      e.data,
    ]),
  );

  /// Text safe in file names.
  String get name =>
      '${strokes}s${strokeSum.toRadixString(36)}-${elements}e${elementSum.toRadixString(36)}';

  @override
  bool operator ==(Object other) =>
      other is ChunkDigest &&
      other.strokes == strokes &&
      other.strokeSum == strokeSum &&
      other.elements == elements &&
      other.elementSum == elementSum;

  @override
  int get hashCode => Object.hash(strokes, strokeSum, elements, elementSum);

  @override
  String toString() => 'ChunkDigest($name)';

  /// Two FNV-1a hashes of [text] combined into 48 bits, with arithmetic
  /// that is exact on the web too (no 64-bit products or shifts).
  static int _hash48(String text) {
    var a = 0x811c9dc5, b = 0x5bd1e995;
    for (final unit in text.codeUnits) {
      a = _mul32((a ^ unit) & 0xffffffff, 0x01000193);
      b = _mul32((b ^ unit) & 0xffffffff, 1000003);
    }
    return a + (b & 0xffff) * 0x100000000;
  }

  /// `a * b mod 2^32` for 32-bit [a] and a multiplier [b] below 2^25.
  static int _mul32(int a, int b) =>
      ((a & 0xffff) * b + ((((a >>> 16) * b) & 0xffff) * 0x10000)) % 0x100000000;
}
