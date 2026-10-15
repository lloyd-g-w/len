import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Two connections to one file (the app's and a pull worker's): a write
/// waits for the other's transaction, up to [AppDatabase.busyTimeoutMs].
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('len-busy-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test("a write waits for another connection's transaction instead of failing", () async {
    final path = '${dir.path}/len.db';
    final app = AppDatabase.open(path);
    addTearDown(app.close);
    for (final write in <void Function()>[
      () => app.transaction(() => app.execute("INSERT INTO settings VALUES ('a', '1')")),
      () => app.db.execute("INSERT INTO settings VALUES ('b', '2')"),
    ]) {
      final locked = ReceivePort();
      final exit = ReceivePort();
      await Isolate.spawn(_holdLock, (path, locked.sendPort), onExit: exit.sendPort);
      await locked.first;
      write();
      await exit.first;
    }
    expect(app.db.select("SELECT COUNT(*) AS n FROM settings WHERE key IN ('a', 'b')"), [
      {'n': 2},
    ]);
  });
}

/// Holds the write lock of the database at the path for a while (as a pull
/// worker's slice does, only longer), saying when it has it.
void _holdLock((String, SendPort) args) {
  final (path, locked) = args;
  final other = sqlite3.open(path)..execute('BEGIN IMMEDIATE');
  locked.send(true);
  sleep(const Duration(milliseconds: 400));
  other
    ..execute('COMMIT')
    ..close();
}
