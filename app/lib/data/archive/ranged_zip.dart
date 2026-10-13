import 'dart:math' as math;

import 'ranged_input.dart';

/// Loads what the zip decoder reads of a [RangedFile] when it opens it:
/// the end of central directory record (and its zip64 counterpart), the
/// central directory, every entry's local header and, for entries written
/// as they streamed, the data descriptor after its data. Not the data:
/// each entry's is loaded when it is read ([RangedInput.loadNext]).
abstract final class RangedZip {
  static const _eocd = 0x06054b50, _zip64Locator = 0x07064b50, _central = 0x02014b50;

  /// The end of central directory record (22 bytes) and its comment.
  static const _tail = 22 + 0xFFFF;

  /// Room for a local header's name and extra field when first loaded.
  static const _headerRoom = 512;

  /// Loads [file]'s zip structure; a file that isn't a zip is left for
  /// the decoder to reject.
  static Future<void> prepare(RangedFile file) async {
    final size = file.size;
    final tailStart = math.max(0, size - _tail - 20);
    await file.load(tailStart, size, keep: true);
    final eocd = _findEocd(file, tailStart);
    if (eocd == null) return;
    var dirSize = _u32(file, eocd + 12), dirOffset = _u32(file, eocd + 16);
    if (eocd - 20 >= 0 && _u32(file, eocd - 20) == _zip64Locator) {
      final record = _u64(file, eocd - 20 + 8);
      await file.load(record, record + 56, keep: true);
      dirSize = _u64(file, record + 40);
      dirOffset = _u64(file, record + 48);
    }
    if (dirOffset + dirSize > size) return;
    await file.load(dirOffset, dirOffset + dirSize, keep: true);

    final entries = <({int header, int size})>[];
    var at = dirOffset;
    while (at + 46 <= dirOffset + dirSize && _u32(file, at) == _central) {
      var compressed = _u32(file, at + 20), uncompressed = _u32(file, at + 24);
      final nameLength = _u16(file, at + 28), extraLength = _u16(file, at + 30);
      final commentLength = _u16(file, at + 32);
      var header = _u32(file, at + 42);
      // Zip64: the sizes and offset that don't fit, in this order.
      var extra = at + 46 + nameLength;
      final extraEnd = extra + extraLength;
      while (extra + 4 <= extraEnd) {
        final id = _u16(file, extra), length = _u16(file, extra + 2);
        if (id == 1) {
          var field = extra + 4;
          if (uncompressed == 0xFFFFFFFF) {
            uncompressed = _u64(file, field);
            field += 8;
          }
          if (compressed == 0xFFFFFFFF) {
            compressed = _u64(file, field);
            field += 8;
          }
          if (header == 0xFFFFFFFF) header = _u64(file, field);
        }
        extra += 4 + length;
      }
      entries.add((header: header, size: compressed));
      at = extraEnd + commentLength;
    }

    await file.keepAll([for (final e in entries) (e.header, e.header + 30 + _headerRoom)]);
    final more = <(int, int)>[];
    for (final e in entries) {
      if (e.header + 30 > size) continue;
      final end = e.header + 30 + _u16(file, e.header + 26) + _u16(file, e.header + 28);
      if (end > e.header + 30 + _headerRoom) more.add((e.header, end));
      // The descriptor (flagged in the local header only): an optional
      // signature, the checksum and two sizes (8 bytes each with zip64).
      if (_u16(file, e.header + 6) & 0x08 != 0) more.add((end + e.size, end + e.size + 24));
    }
    await file.keepAll([
      for (final (s, e) in more)
        if (s < size) (s, math.min(e, size)),
    ]);
  }

  static int? _findEocd(RangedFile file, int from) {
    for (var at = file.size - 22; at >= from; at--) {
      if (_u32(file, at) == _eocd) return at;
    }
    return null;
  }

  static int _u16(RangedFile f, int at) => f.byteAt(at) | f.byteAt(at + 1) << 8;

  static int _u32(RangedFile f, int at) => _u16(f, at) + _u16(f, at + 2) * 0x10000;

  static int _u64(RangedFile f, int at) => _u32(f, at) + _u32(f, at + 4) * 0x100000000;
}
