/// Stream filter decoding (PDF 32000-1 §7.4): FlateDecode (with PNG/TIFF
/// predictors), ASCIIHexDecode and ASCII85Decode.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'cos.dart';
import 'pdf_bytes.dart';

/// Resolves an indirect reference (identity for direct objects).
typedef CosResolver = CosObject? Function(CosObject? object);

/// The filter names of [dict] (`/Filter` name or array), resolved.
List<String> streamFilters(CosDict dict, CosResolver resolve) {
  final f = resolve(dict['Filter']);
  if (f is CosName) return [f.name];
  if (f is CosArray) {
    return [for (final e in f.items) resolve(e).asName ?? (throw PdfReadException('Bad /Filter'))];
  }
  return const [];
}

/// Decodes the data of [stream], applying all of its filters.
///
/// Throws [PdfReadException] for unsupported filters or corrupt data.
Uint8List decodeStreamData(CosStream stream, CosResolver resolve) {
  if (stream.dict['F'] != null) throw PdfReadException('External stream data (/F)');
  final filters = streamFilters(stream.dict, resolve);
  final parmsObj = resolve(stream.dict['DecodeParms'] ?? stream.dict['DP']);
  var data = stream.raw;
  for (var i = 0; i < filters.length; i++) {
    final p = parmsObj is CosArray
        ? (i < parmsObj.items.length ? resolve(parmsObj.items[i]) : null)
        : parmsObj;
    final parms = p is CosDict ? p : null;
    data = switch (filters[i]) {
      'FlateDecode' || 'Fl' => applyPredictor(inflateZlib(data), parms, resolve),
      'ASCIIHexDecode' || 'AHx' => decodeAsciiHex(data),
      'ASCII85Decode' || 'A85' => decodeAscii85(data),
      final other => throw PdfReadException('Unsupported filter /$other'),
    };
  }
  return data;
}

/// Inflates zlib data, tolerating a bad checksum or a missing header.
Uint8List inflateZlib(Uint8List data) {
  try {
    return ZLibDecoder().decodeBytes(data, verify: false);
  } catch (_) {
    try {
      return Inflate(data.length > 2 ? data.sublist(2) : data).getBytes();
    } catch (_) {
      throw PdfReadException('Corrupt FlateDecode data');
    }
  }
}

/// Undoes a `/Predictor` (2 = TIFF, ≥ 10 = PNG) described by [parms].
Uint8List applyPredictor(Uint8List data, CosDict? parms, CosResolver resolve) {
  int param(String key, int def) => resolve(parms?[key]).asInt ?? def;
  final predictor = param('Predictor', 1);
  if (predictor <= 1) return data;
  final colors = param('Colors', 1);
  final bpc = param('BitsPerComponent', 8);
  final columns = param('Columns', 1);
  final bpp = (colors * bpc + 7) ~/ 8;
  final rowLen = (columns * colors * bpc + 7) ~/ 8;
  if (bpp < 1 || rowLen < 1) throw PdfReadException('Bad predictor parameters');
  if (predictor == 2) {
    if (bpc != 8) throw PdfReadException('Unsupported TIFF predictor with $bpc bits');
    final out = Uint8List.fromList(data);
    for (var row = 0; row < out.length; row += rowLen) {
      for (var i = bpp; i < rowLen && row + i < out.length; i++) {
        out[row + i] = (out[row + i] + out[row + i - bpp]) & 0xff;
      }
    }
    return out;
  }
  if (predictor < 10) throw PdfReadException('Unsupported predictor $predictor');
  final rows = (data.length + rowLen) ~/ (rowLen + 1);
  final out = Uint8List(rows * rowLen);
  var outLen = 0;
  var prev = 0; // start of the previous row in out, or -1
  for (var src = 0, r = 0; src < data.length; src += rowLen + 1, r++) {
    final type = data[src];
    final n = (data.length - src - 1).clamp(0, rowLen);
    final cur = r * rowLen;
    for (var i = 0; i < n; i++) {
      final x = data[src + 1 + i];
      final a = i >= bpp ? out[cur + i - bpp] : 0;
      final b = r > 0 ? out[prev + i] : 0;
      final c = r > 0 && i >= bpp ? out[prev + i - bpp] : 0;
      final v = switch (type) {
        0 => x,
        1 => x + a,
        2 => x + b,
        3 => x + ((a + b) ~/ 2),
        4 => x + _paeth(a, b, c),
        _ => throw PdfReadException('Bad PNG predictor row type $type'),
      };
      out[cur + i] = v & 0xff;
    }
    outLen = cur + n;
    prev = cur;
  }
  return Uint8List.sublistView(out, 0, outLen);
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

/// Decodes ASCIIHexDecode data (stops at `>`).
Uint8List decodeAsciiHex(Uint8List data) {
  final out = BytesBuilder(copy: false);
  int? high;
  for (final c in data) {
    if (c == 0x3e) break;
    if (isPdfWhite(c)) continue;
    final v = hexDigitValue(c);
    if (v < 0) throw PdfReadException('Bad ASCIIHex digit');
    if (high == null) {
      high = v;
    } else {
      out.addByte(high * 16 + v);
      high = null;
    }
  }
  if (high != null) out.addByte(high * 16);
  return out.toBytes();
}

/// Decodes ASCII85Decode data (stops at `~>`).
Uint8List decodeAscii85(Uint8List data) {
  final out = BytesBuilder(copy: false);
  final group = <int>[];
  void flush(int count) {
    var v = 0;
    for (var i = 0; i < 5; i++) {
      v = v * 85 + (i < group.length ? group[i] : 84);
    }
    // Byte extraction by division: values reach 2^32, beyond web-safe shifts.
    final bytes = [v ~/ 16777216 % 256, v ~/ 65536 % 256, v ~/ 256 % 256, v % 256];
    for (var i = 0; i < count; i++) {
      out.addByte(bytes[i]);
    }
    group.clear();
  }

  for (final c in data) {
    if (c == 0x7e) break;
    if (isPdfWhite(c)) continue;
    if (c == 0x7a && group.isEmpty) {
      out.add(const [0, 0, 0, 0]);
      continue;
    }
    if (c < 0x21 || c > 0x75) throw PdfReadException('Bad ASCII85 character');
    group.add(c - 0x21);
    if (group.length == 5) flush(4);
  }
  if (group.length == 1) throw PdfReadException('Bad ASCII85 final group');
  if (group.isNotEmpty) flush(group.length - 1);
  return out.toBytes();
}
