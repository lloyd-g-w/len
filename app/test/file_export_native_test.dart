import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
