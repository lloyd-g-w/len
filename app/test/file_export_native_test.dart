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
    final now = DateTime.now();
    final stray = File('${dir.parent.path}/Page 3.png')..writeAsStringSync('stray');
    for (final path in [dir.path, stray.path]) {
      final s = now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000;
      expect(Process.runSync('touch', ['-d', '@$s', path]).exitCode, 0);
    }
    final recent = await freshExportDir(tmp, now: now);
    final shared = File('${recent.path}/Page 3.png')..writeAsStringSync('new');
    await freshExportDir(tmp, now: now);
    expect(old.existsSync(), isFalse);
    expect(stray.existsSync(), isFalse);
    // Maybe still being read by the app it was shared to.
    expect(shared.existsSync(), isTrue);
  });

  test('each share has a folder of its own: sharing a file of the same name again never '
      'rewrites one an app may still be reading', () async {
    final tmp = Directory.systemTemp.createTempSync('len_share_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final first = await freshExportDir(tmp);
    final file = File('${first.path}/Notes.pdf')..writeAsStringSync('pages 1-3');
    final second = await freshExportDir(tmp);
    expect(second.path, isNot(first.path));
    File('${second.path}/Notes.pdf').writeAsStringSync('page 5');
    expect(file.readAsStringSync(), 'pages 1-3');
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

  test('the ZIP is named as exported files are; names inside never clash on any system', () {
    final files = [
      for (final name in ['Physics.pdf', 'physics.pdf', 'PHYSICS.PDF', 'physics (2).pdf'])
        (bytes: Uint8List.fromList(name.codeUnits), name: name),
    ];
    expect(zipOf(files, subject: 'CON').name, 'CON_.zip');
    expect(zipOf(files, subject: 'Notes...').name, 'Notes.zip');
    expect(zipOf(files, subject: 'a' * 300).name, '${'a' * 100}.zip');
    expect(zipOf(files, subject: ' ?? ').name, 'Len export.zip');
    final names = [for (final f in ZipDecoder().decodeBytes(zipOf(files).bytes).files) f.name];
    expect(names, ['Physics.pdf', 'physics (2).pdf', 'PHYSICS (3).PDF', 'physics (2) (2).pdf']);
    expect({for (final n in names) n.toLowerCase()}, hasLength(4));
  });
}
