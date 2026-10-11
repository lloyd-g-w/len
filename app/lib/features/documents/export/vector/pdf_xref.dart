/// Cross-reference reading (PDF 32000-1 §7.5.4–7.5.8): classic tables,
/// cross-reference streams, hybrid files and `/Prev` chains, plus a
/// whole-file scan used when the cross-reference data is broken.
library;

import 'dart:typed_data';

import 'cos.dart';
import 'pdf_bytes.dart';
import 'pdf_filters.dart';
import 'pdf_lexer.dart';

/// One cross-reference entry.
class XrefEntry {
  /// A free entry.
  const XrefEntry.free() : type = 0, a = 0, b = 0;

  /// An object stored at byte [offset] with generation [gen].
  const XrefEntry.offset(int offset, int gen) : type = 1, a = offset, b = gen;

  /// An object stored at [index] in object stream number [stream].
  const XrefEntry.compressed(int stream, int index) : type = 2, a = stream, b = index;

  /// 0 = free, 1 = byte offset, 2 = in an object stream.
  final int type;

  /// The byte offset (type 1) or the object stream number (type 2).
  final int a;

  /// The generation (type 1) or the index in the object stream (type 2).
  final int b;
}

/// The merged result of a cross-reference chain.
class XrefData {
  /// Creates the data.
  XrefData(this.entries, this.trailer);

  /// Entries by object number; newer sections win.
  final Map<int, XrefEntry> entries;

  /// The newest trailer, completed with keys only present in older ones.
  final CosDict trailer;
}

CosObject? _direct(CosObject? o) => o is CosRef ? null : o;

/// The byte offset given after the last `startxref` keyword.
int findStartXref(Uint8List bytes) {
  final i = lastIndexOfBytes(bytes, 'startxref'.codeUnits);
  if (i < 0) throw PdfReadException('No startxref');
  final offset = PdfParser(bytes, pos: i + 9).tryReadInt();
  if (offset == null) throw PdfReadException('Bad startxref');
  return offset;
}

/// Reads the cross-reference chain starting at `startxref`, following `/Prev`
/// (and `/XRefStm` in hybrid files). Throws [PdfReadException] on failure.
XrefData readXrefChain(Uint8List bytes) {
  final entries = <int, XrefEntry>{};
  final trailer = <String, CosObject>{};
  final visited = <int>{};
  int? offset = findStartXref(bytes);
  while (offset != null && visited.add(offset)) {
    final (section, dict) = _readSection(bytes, offset);
    section.forEach((k, v) => entries.putIfAbsent(k, () => v));
    for (final e in dict.entries.entries) {
      if (e.key != 'Prev' && e.key != 'XRefStm') trailer.putIfAbsent(e.key, () => e.value);
    }
    offset = _direct(dict['Prev']).asInt;
  }
  return XrefData(entries, CosDict(trailer));
}

(Map<int, XrefEntry>, CosDict) _readSection(Uint8List bytes, int offset) {
  if (offset < 0 || offset >= bytes.length) throw PdfReadException('Bad xref offset $offset');
  final p = PdfParser(bytes, pos: offset);
  if (!p.tryKeyword('xref')) return readXrefStream(bytes, offset);
  final entries = <int, XrefEntry>{};
  while (true) {
    final start = p.tryReadInt();
    if (start == null) break;
    final count = p.tryReadInt();
    if (count == null) throw PdfReadException('Bad xref subsection');
    for (var i = 0; i < count; i++) {
      final off = p.tryReadInt(), gen = p.tryReadInt(), kind = p.readToken();
      if (off == null || gen == null || (kind != 'n' && kind != 'f')) {
        throw PdfReadException('Bad xref entry');
      }
      entries.putIfAbsent(
        start + i,
        () => kind == 'n' && off > 0 ? XrefEntry.offset(off, gen) : const XrefEntry.free(),
      );
    }
  }
  if (!p.tryKeyword('trailer')) throw PdfReadException('Missing trailer');
  final trailer = p.parseObject();
  if (trailer is! CosDict) throw PdfReadException('Bad trailer');
  final stm = _direct(trailer['XRefStm']).asInt;
  if (stm != null) {
    // Hybrid file: the hidden stream lists the compressed objects.
    final (streamEntries, _) = readXrefStream(bytes, stm);
    streamEntries.forEach((number, e) {
      if (e.type != 0) entries[number] = e;
    });
  }
  return (entries, trailer);
}

/// Reads a cross-reference stream object at [offset].
(Map<int, XrefEntry>, CosDict) readXrefStream(Uint8List bytes, int offset) {
  final obj = PdfParser(bytes, pos: offset).parseIndirectObject().object;
  if (obj is! CosStream || (obj.dict['W'] == null)) {
    throw PdfReadException('Expected a cross-reference stream at $offset');
  }
  final dict = obj.dict;
  final w = _direct(dict['W']);
  if (w is! CosArray || w.items.length < 3) throw PdfReadException('Bad /W');
  final widths = [for (final x in w.items.take(3)) x.asInt ?? -1];
  if (widths.any((x) => x < 0 || x > 8)) throw PdfReadException('Bad /W');
  final size = _direct(dict['Size']).asInt ?? 0;
  final indexObj = _direct(dict['Index']);
  final index = indexObj is CosArray ? [for (final x in indexObj.items) x.asInt ?? 0] : [0, size];
  final data = decodeStreamData(obj, _direct);
  final rowSize = widths[0] + widths[1] + widths[2];
  if (rowSize == 0) throw PdfReadException('Bad /W');
  final entries = <int, XrefEntry>{};
  var pos = 0;
  int field(int width, int def) {
    if (width == 0) return def;
    var v = 0;
    for (var i = 0; i < width; i++) {
      v = v * 256 + data[pos++];
    }
    return v;
  }

  for (var s = 0; s + 1 < index.length; s += 2) {
    for (var i = 0; i < index[s + 1] && pos + rowSize <= data.length; i++) {
      final type = field(widths[0], 1), f1 = field(widths[1], 0), f2 = field(widths[2], 0);
      final entry = switch (type) {
        0 => const XrefEntry.free(),
        1 => XrefEntry.offset(f1, f2),
        2 => XrefEntry.compressed(f1, f2),
        _ => null, // unknown types are references to the null object
      };
      if (entry != null) entries.putIfAbsent(index[s] + i, () => entry);
    }
  }
  return (entries, dict);
}

/// The result of scanning a whole file for `N G obj` headers.
class ScanResult {
  /// Creates a result.
  ScanResult(this.offsets, this.trailers);

  /// Object offsets by number; later definitions win.
  final Map<int, XrefEntry> offsets;

  /// Dictionaries following `trailer` keywords, in file order.
  final List<CosDict> trailers;
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

/// Scans [bytes] for every `N G obj` header and `trailer` dictionary.
ScanResult scanObjects(Uint8List bytes) {
  final offsets = <int, XrefEntry>{};
  final obj = 'obj'.codeUnits;
  for (var i = indexOfBytes(bytes, obj); i >= 0; i = indexOfBytes(bytes, obj, i + 3)) {
    if (i + 3 < bytes.length && !isPdfWhite(bytes[i + 3]) && !isPdfDelimiter(bytes[i + 3])) {
      continue;
    }
    var j = i - 1;
    while (j >= 0 && isPdfWhite(bytes[j])) {
      j--;
    }
    final genEnd = j + 1;
    while (j >= 0 && _isDigit(bytes[j])) {
      j--;
    }
    if (j + 1 == genEnd || j < 0 || !isPdfWhite(bytes[j])) continue;
    final genStart = j + 1;
    while (j >= 0 && isPdfWhite(bytes[j])) {
      j--;
    }
    final numEnd = j + 1;
    while (j >= 0 && _isDigit(bytes[j])) {
      j--;
    }
    if (j + 1 == numEnd || (j >= 0 && bytes[j] == 0x2e)) continue;
    final number = int.tryParse(String.fromCharCodes(bytes, j + 1, numEnd));
    final gen = int.tryParse(String.fromCharCodes(bytes, genStart, genEnd));
    if (number != null && gen != null) offsets[number] = XrefEntry.offset(j + 1, gen);
  }
  final trailers = <CosDict>[];
  final kw = 'trailer'.codeUnits;
  for (var i = indexOfBytes(bytes, kw); i >= 0; i = indexOfBytes(bytes, kw, i + kw.length)) {
    try {
      final t = PdfParser(bytes, pos: i + kw.length).parseObject();
      if (t is CosDict) trailers.add(t);
    } on PdfReadException {
      // Not a usable trailer.
    }
  }
  return ScanResult(offsets, trailers);
}
