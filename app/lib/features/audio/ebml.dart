import 'dart:typed_data';

/// One EBML element (Matroska / WebM) in a byte buffer: its [id] (marker
/// bits included, as the specs write them), where it [start]s, where its
/// data starts ([dataStart]) and ends ([end]; the buffer's end or the end
/// of its parent when its size is [unknown], as recorders write live
/// streams).
class EbmlElement {
  const EbmlElement(this.id, this.start, this.dataStart, this.end, {this.unknown = false});

  final int id, start, dataStart, end;
  final bool unknown;
}

/// Reading and writing EBML, the binary format of Matroska and WebM.
/// Integers are built by multiplication, never 64-bit shifts, so it works
/// in browsers (sizes up to 2^53).
abstract final class Ebml {
  /// The element at [pos] of [d] (ending at [limit] at the latest), or null
  /// when there is none: a malformed or truncated header, or data running
  /// past [limit].
  static EbmlElement? read(Uint8List d, int pos, int limit) {
    if (pos >= limit) return null;
    final idLength = _vintLength(d[pos]);
    if (idLength == null || idLength > 4 || pos + idLength > limit) return null;
    var id = 0;
    for (var i = 0; i < idLength; i++) {
      id = id * 256 + d[pos + i];
    }
    final sizeAt = pos + idLength;
    if (sizeAt >= limit) return null;
    final sizeLength = _vintLength(d[sizeAt]);
    if (sizeLength == null || sizeAt + sizeLength > limit) return null;
    final mask = 0xFF >> sizeLength;
    var size = d[sizeAt] & mask;
    var allOnes = size == mask;
    for (var i = 1; i < sizeLength; i++) {
      final b = d[sizeAt + i];
      allOnes = allOnes && b == 0xFF;
      size = size * 256 + b;
    }
    final dataStart = sizeAt + sizeLength;
    if (allOnes) return EbmlElement(id, pos, dataStart, limit, unknown: true);
    if (size > limit - dataStart) return null;
    return EbmlElement(id, pos, dataStart, dataStart + size);
  }

  /// The children of [d]'s bytes [from]…[to], or null when they don't
  /// parse.
  static List<EbmlElement>? children(Uint8List d, int from, int to) {
    final out = <EbmlElement>[];
    for (var pos = from; pos < to;) {
      final e = read(d, pos, to);
      if (e == null || e.unknown) return null;
      out.add(e);
      pos = e.end;
    }
    return out;
  }

  /// The unsigned integer in [e]'s data (up to 7 bytes), or null.
  static int? uint(Uint8List d, EbmlElement e) {
    final length = e.end - e.dataStart;
    if (length > 7) return null;
    var v = 0;
    for (var i = e.dataStart; i < e.end; i++) {
      v = v * 256 + d[i];
    }
    return v;
  }

  /// The length of the variable-length integer starting with [first]
  /// (1…8 bytes), or null for a zero byte.
  static int? _vintLength(int first) {
    for (var n = 1; n <= 8; n++) {
      if (first & (0x100 >> n) != 0) return n;
    }
    return null;
  }

  /// An element with [id] around [body].
  static Uint8List element(int id, List<Uint8List> body) {
    final length = body.fold<int>(0, (sum, b) => sum + b.length);
    final out = BytesBuilder(copy: false)
      ..add(_idBytes(id))
      ..add(_size(length));
    body.forEach(out.add);
    return out.takeBytes();
  }

  /// An unsigned integer element.
  static Uint8List uintElement(int id, int value) {
    final bytes = <int>[];
    for (var v = value; bytes.isEmpty || v > 0; v ~/= 256) {
      bytes.insert(0, v % 256);
    }
    return element(id, [Uint8List.fromList(bytes)]);
  }

  /// A float element (8 bytes).
  static Uint8List floatElement(int id, double value) =>
      element(id, [Uint8List(8)..buffer.asByteData().setFloat64(0, value)]);

  static Uint8List _idBytes(int id) {
    final bytes = <int>[];
    for (var v = id; v > 0; v ~/= 256) {
      bytes.insert(0, v % 256);
    }
    return Uint8List.fromList(bytes);
  }

  /// [value] as an EBML size in the fewest bytes (all ones is reserved for
  /// "unknown").
  static Uint8List _size(int value) {
    var n = 1;
    var limit = 127; // 2^(7n) − 1
    while (value >= limit) {
      n++;
      limit = limit * 128 + 127;
    }
    final out = Uint8List(n);
    var v = value;
    for (var i = n - 1; i >= 0; i--) {
      out[i] = v % 256;
      v ~/= 256;
    }
    out[0] |= 0x100 >> n;
    return out;
  }
}
