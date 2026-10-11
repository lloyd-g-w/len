/// Lexer and parser for PDF objects (PDF 32000-1 §7.2–7.3).
library;

import 'dart:typed_data';

import 'cos.dart';
import 'pdf_bytes.dart';

/// Resolves an indirect `/Length` of a stream; returns null when unknown.
typedef LengthResolver = int? Function(CosRef ref);

/// An indirect object read by [PdfParser.parseIndirectObject].
typedef IndirectObject = ({int number, int gen, CosObject object});

/// A recursive-descent parser over a byte buffer, positioned at [pos].
class PdfParser {
  /// Creates a parser over [bytes] starting at [pos].
  PdfParser(this.bytes, {this.pos = 0, this.resolveLength});

  /// The whole input.
  final Uint8List bytes;

  /// The current read position.
  int pos;

  /// Used for streams whose `/Length` is an indirect reference.
  final LengthResolver? resolveLength;

  static final _endstream = 'endstream'.codeUnits;
  static final _intToken = RegExp(r'^[+-]?[0-9]+$');
  static final _realToken = RegExp(r'^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)$');

  /// Whether only whitespace/comments remain.
  bool get atEnd {
    skipWhitespace();
    return pos >= bytes.length;
  }

  /// Skips whitespace and `%` comments.
  void skipWhitespace() {
    while (pos < bytes.length) {
      final c = bytes[pos];
      if (isPdfWhite(c)) {
        pos++;
      } else if (c == 0x25) {
        while (pos < bytes.length && bytes[pos] != 0x0a && bytes[pos] != 0x0d) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  /// Reads a run of regular (non-white, non-delimiter) bytes.
  String readToken() {
    skipWhitespace();
    final start = pos;
    while (pos < bytes.length && !isPdfWhite(bytes[pos]) && !isPdfDelimiter(bytes[pos])) {
      pos++;
    }
    return String.fromCharCodes(bytes, start, pos);
  }

  /// Reads a non-negative integer token, or returns null (position restored).
  int? tryReadInt() {
    final save = pos;
    final t = readToken();
    final v = t.isEmpty || t.codeUnits.any((c) => c < 0x30 || c > 0x39) ? null : int.tryParse(t);
    if (v == null) pos = save;
    return v;
  }

  /// Reads the keyword [k] or returns false (position restored).
  bool tryKeyword(String k) {
    final save = pos;
    if (readToken() == k) return true;
    pos = save;
    return false;
  }

  Never _error(String what) => throw PdfReadException('$what at offset $pos');

  /// Parses one direct object (or reference `n g R`).
  CosObject parseObject() {
    skipWhitespace();
    if (pos >= bytes.length) _error('Unexpected end of data');
    final c = bytes[pos];
    switch (c) {
      case 0x2f:
        return _parseName();
      case 0x28:
        return _parseLiteralString();
      case 0x5b:
        pos++;
        final items = <CosObject>[];
        while (true) {
          skipWhitespace();
          if (pos >= bytes.length) _error('Unterminated array');
          if (bytes[pos] == 0x5d) {
            pos++;
            return CosArray(items);
          }
          items.add(parseObject());
        }
      case 0x3c:
        if (pos + 1 < bytes.length && bytes[pos + 1] == 0x3c) return _parseDict();
        return _parseHexString();
    }
    if (isPdfDelimiter(c)) _error('Unexpected delimiter ${String.fromCharCode(c)}');
    final start = pos;
    final t = readToken();
    switch (t) {
      case 'true':
        return const CosBool(true);
      case 'false':
        return const CosBool(false);
      case 'null':
        return CosNull.instance;
    }
    if (_intToken.hasMatch(t)) {
      final i = int.tryParse(t);
      if (i != null) {
        if (i >= 0) {
          final save = pos;
          final gen = tryReadInt();
          if (gen != null && tryKeyword('R')) return CosRef(i, gen);
          pos = save;
        }
        return CosNumber(i);
      }
    }
    if (_realToken.hasMatch(t)) return CosNumber(double.parse(t.replaceFirst('+', '')));
    pos = start;
    _error('Unexpected token "$t"');
  }

  CosName _parseName() {
    pos++; // '/'
    final out = StringBuffer();
    while (pos < bytes.length && !isPdfWhite(bytes[pos]) && !isPdfDelimiter(bytes[pos])) {
      final c = bytes[pos++];
      if (c == 0x23 && pos + 1 < bytes.length) {
        final h = hexDigitValue(bytes[pos]), l = hexDigitValue(bytes[pos + 1]);
        if (h >= 0 && l >= 0) {
          out.writeCharCode(h * 16 + l);
          pos += 2;
          continue;
        }
      }
      out.writeCharCode(c);
    }
    return CosName(out.toString());
  }

  CosString _parseLiteralString() {
    pos++; // '('
    final out = BytesBuilder(copy: false);
    var depth = 1;
    while (true) {
      if (pos >= bytes.length) _error('Unterminated string');
      final c = bytes[pos++];
      if (c == 0x28) {
        depth++;
      } else if (c == 0x29) {
        if (--depth == 0) return CosString(out.toBytes());
      } else if (c == 0x0d) {
        if (pos < bytes.length && bytes[pos] == 0x0a) pos++;
        out.addByte(0x0a);
        continue;
      } else if (c == 0x5c) {
        if (pos >= bytes.length) _error('Unterminated string');
        final e = bytes[pos++];
        switch (e) {
          case 0x6e:
            out.addByte(0x0a);
          case 0x72:
            out.addByte(0x0d);
          case 0x74:
            out.addByte(0x09);
          case 0x62:
            out.addByte(0x08);
          case 0x66:
            out.addByte(0x0c);
          case 0x0d:
            if (pos < bytes.length && bytes[pos] == 0x0a) pos++;
          case 0x0a:
            break; // line continuation
          default:
            if (e >= 0x30 && e <= 0x37) {
              var v = e - 0x30;
              for (var n = 0; n < 2 && pos < bytes.length; n++) {
                final d = bytes[pos];
                if (d < 0x30 || d > 0x37) break;
                v = v * 8 + d - 0x30;
                pos++;
              }
              out.addByte(v & 0xff);
            } else {
              out.addByte(e); // \( \) \\ and unknown escapes
            }
        }
        continue;
      }
      out.addByte(c);
    }
  }

  CosString _parseHexString() {
    pos++; // '<'
    final out = BytesBuilder(copy: false);
    int? high;
    while (true) {
      if (pos >= bytes.length) _error('Unterminated hex string');
      final c = bytes[pos++];
      if (c == 0x3e) break;
      if (isPdfWhite(c)) continue;
      final v = hexDigitValue(c);
      if (v < 0) _error('Bad hex digit');
      if (high == null) {
        high = v;
      } else {
        out.addByte(high * 16 + v);
        high = null;
      }
    }
    if (high != null) out.addByte(high * 16);
    return CosString(out.toBytes(), hex: true);
  }

  CosDict _parseDict() {
    pos += 2; // '<<'
    final entries = <String, CosObject>{};
    while (true) {
      skipWhitespace();
      if (pos + 1 < bytes.length && bytes[pos] == 0x3e && bytes[pos + 1] == 0x3e) {
        pos += 2;
        return CosDict(entries);
      }
      if (pos >= bytes.length) _error('Unterminated dictionary');
      if (bytes[pos] != 0x2f) _error('Expected a name key in dictionary');
      final key = _parseName().name;
      skipWhitespace();
      if (pos + 1 < bytes.length && bytes[pos] == 0x3e && bytes[pos + 1] == 0x3e) continue;
      entries[key] = parseObject();
    }
  }

  /// Parses `n g obj <object> [stream…endstream] [endobj]` at [pos].
  IndirectObject parseIndirectObject() {
    final number = tryReadInt();
    final gen = number == null ? null : tryReadInt();
    if (number == null || gen == null || !tryKeyword('obj')) _error('Expected "N G obj"');
    var object = parseObject();
    if (object is CosDict) {
      final save = pos;
      if (tryKeyword('stream')) {
        object = CosStream(object, _readStreamData(object));
      } else {
        pos = save;
      }
    }
    final save = pos;
    if (!tryKeyword('endobj')) pos = save;
    return (number: number, gen: gen, object: object);
  }

  Uint8List _readStreamData(CosDict dict) {
    if (pos < bytes.length && bytes[pos] == 0x0d) pos++;
    if (pos < bytes.length && bytes[pos] == 0x0a) pos++;
    final start = pos;
    final lengthObj = dict['Length'];
    final length = lengthObj is CosRef ? resolveLength?.call(lengthObj) : lengthObj.asInt;
    if (length != null && length >= 0 && start + length <= bytes.length) {
      final check = PdfParser(bytes, pos: start + length);
      if (check.tryKeyword('endstream')) {
        pos = check.pos;
        return Uint8List.sublistView(bytes, start, start + length);
      }
    }
    final end = indexOfBytes(bytes, _endstream, start);
    if (end < 0) _error('Missing endstream');
    var dataEnd = end;
    if (dataEnd > start && bytes[dataEnd - 1] == 0x0a) dataEnd--;
    if (dataEnd > start && bytes[dataEnd - 1] == 0x0d) dataEnd--;
    pos = end + _endstream.length;
    return Uint8List.sublistView(bytes, start, dataEnd);
  }
}
