import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A real TrueType font file to import as a user font: the bundled
/// Caveat (any TTF does; this one draws visibly unlike Inter).
Uint8List caveatFile() => File('assets/fonts/Caveat-Regular.ttf').readAsBytesSync();

/// A minimal sfnt file with [tag] (`0x00010000`, `OTTO`, …), empty tables
/// [tables] and a `name` table holding [names] (Windows, English), for
/// reading names without a real font.
Uint8List sfnt(int tag, List<String> tables, Map<int, String> names) {
  final name = _nameTable(names);
  final all = {for (final t in tables) t: Uint8List(4), 'name': name};
  final header = 12 + 16 * all.length;
  final out = BytesBuilder();
  final dir = ByteData(header)
    ..setUint32(0, tag)
    ..setUint16(4, all.length);
  var offset = header;
  var i = 0;
  for (final MapEntry(:key, :value) in all.entries) {
    final at = 12 + i++ * 16;
    final codes = ascii.encode(key.padRight(4));
    for (var k = 0; k < 4; k++) {
      dir.setUint8(at + k, codes[k]);
    }
    dir
      ..setUint32(at + 8, offset)
      ..setUint32(at + 12, value.length);
    offset += value.length;
  }
  out.add(dir.buffer.asUint8List());
  for (final t in all.values) {
    out.add(t);
  }
  return out.toBytes();
}

Uint8List _nameTable(Map<int, String> names) {
  final strings = BytesBuilder();
  final records = ByteData(12 * names.length);
  var i = 0;
  for (final MapEntry(:key, :value) in names.entries) {
    final utf16 = ByteData(value.length * 2);
    for (var k = 0; k < value.length; k++) {
      utf16.setUint16(k * 2, value.codeUnitAt(k));
    }
    records
      ..setUint16(i * 12, 3)
      ..setUint16(i * 12 + 2, 1)
      ..setUint16(i * 12 + 4, 0x409)
      ..setUint16(i * 12 + 6, key)
      ..setUint16(i * 12 + 8, value.length * 2)
      ..setUint16(i * 12 + 10, strings.length);
    strings.add(utf16.buffer.asUint8List());
    i++;
  }
  final head = ByteData(6)
    ..setUint16(0, 0)
    ..setUint16(2, names.length)
    ..setUint16(4, 6 + 12 * names.length);
  return (BytesBuilder()
        ..add(head.buffer.asUint8List())
        ..add(records.buffer.asUint8List())
        ..add(strings.toBytes()))
      .toBytes();
}
