import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/platform/file_export_api.dart';
import 'package:len/platform/file_export_native.dart';

void main() {
  test('shared files are cleared from the export folder an hour on (UX_AUDIT R22-6)', () async {
    final tmp = Directory.systemTemp.createTempSync('len_share_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final dir = await freshExportDir(tmp);
    final old = File('${dir.path}/Assignment 1.pdf')..writeAsStringSync('old');
    final recent = File('${dir.path}/Page 3.png')..writeAsStringSync('new');
    final now = DateTime.now();
    old.setLastModifiedSync(now.subtract(const Duration(hours: 2)));
    final again = await freshExportDir(tmp, now: now);
    expect(again.path, dir.path);
    expect(old.existsSync(), isFalse);
    // Maybe still being read by the app it was shared to.
    expect(recent.existsSync(), isTrue);
  });

  test('several files download on the web as one ZIP named after the export (R22-7)', () {
    final files = [
      for (final name in ['Physics p1.png', 'Physics p2.png', 'Physics p2.png'])
        (bytes: Uint8List.fromList(name.codeUnits), name: name),
    ];
    final zip = zipOf(files, subject: 'Physics: week 3/4');
    expect(zip.name, 'Physics week 3 4.zip');
    final archive = ZipDecoder().decodeBytes(zip.bytes);
    expect(
      [for (final f in archive.files) f.name],
      ['Physics p1.png', 'Physics p2.png', 'Physics p2 (2).png'],
    );
    expect(String.fromCharCodes(archive.files.first.content), 'Physics p1.png');
    expect(zipOf(files).name, 'Len export.zip');
  });
}
