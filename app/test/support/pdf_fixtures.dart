import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Builds hand-written PDF files byte by byte, recording object offsets.
class RawPdf {
  RawPdf([String version = '1.7']) {
    text('%PDF-$version\n%\u00e2\u00e3\u00cf\u00d3\n');
  }

  final _b = BytesBuilder();

  /// Byte offsets of the objects written so far.
  final offsets = <int, int>{};

  int get length => _b.length;

  void text(String s) => _b.add(latin1.encode(s));

  void bytes(List<int> b) => _b.add(b);

  void obj(int n, String body) {
    offsets[n] = length;
    text('$n 0 obj\n$body\nendobj\n');
  }

  void stream(int n, String dict, List<int> data) {
    offsets[n] = length;
    text('$n 0 obj\n$dict\nstream\n');
    bytes(data);
    text('\nendstream\nendobj\n');
  }

  /// Writes a classic xref table for [only] (default: every object), then the
  /// trailer and `startxref`; returns the table's offset.
  int xrefTable(String trailer, {Iterable<int>? only}) {
    final at = length;
    text('xref\n0 1\n0000000000 65535 f \n');
    for (final n in (only ?? offsets.keys).toList()..sort()) {
      text('$n 1\n${offsets[n]!.toString().padLeft(10, '0')} 00000 n \n');
    }
    text('trailer\n$trailer\nstartxref\n$at\n%%EOF\n');
    return at;
  }

  /// Writes cross-reference stream object [n] with [rows] (object number →
  /// [type, field2, field3]) using `/W [1 4 2]`, optionally PNG-Up predicted.
  int xrefStream(int n, Map<int, List<int>> rows, String extra, {bool predictor = false}) {
    final at = length;
    rows = {
      ...rows,
      n: [1, at, 0],
    };
    final keys = rows.keys.toList()..sort();
    final data = <int>[];
    var prev = List.filled(7, 0);
    for (final k in keys) {
      final [t, a, b] = rows[k]!;
      final row = [
        t,
        a ~/ 16777216 % 256,
        a ~/ 65536 % 256,
        a ~/ 256 % 256,
        a % 256,
        b ~/ 256,
        b % 256,
      ];
      if (predictor) {
        data.add(2);
        for (var i = 0; i < 7; i++) {
          data.add((row[i] - prev[i]) & 0xff);
        }
        prev = row;
      } else {
        data.addAll(row);
      }
    }
    final index = keys.map((k) => '$k 1').join(' ');
    final size = keys.last + 1;
    final parms = predictor ? '/DecodeParms << /Predictor 12 /Columns 7 >>' : '';
    final z = ZLibEncoder().encodeBytes(data);
    stream(
      n,
      '<< /Type /XRef /W [1 4 2] /Index [$index] /Size $size /Filter /FlateDecode $parms '
      '/Length ${z.length} $extra >>',
      z,
    );
    text('startxref\n$at\n%%EOF\n');
    return at;
  }

  Uint8List finish() => _b.toBytes();
}

/// The data and `/First` of an object stream holding [objects].
(Uint8List, int) objectStreamData(List<(int, String)> objects) {
  final header = StringBuffer();
  final body = StringBuffer();
  for (final (n, src) in objects) {
    header.write('$n ${body.length} ');
    body.write('$src\n');
  }
  final first = header.length;
  return (Uint8List.fromList(latin1.encode('$header$body')), first);
}

/// zlib-compresses [s].
Uint8List deflateText(String s) => ZLibEncoder().encodeBytes(latin1.encode(s));
