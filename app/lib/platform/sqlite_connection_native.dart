import 'dart:io' show sleep;

import 'package:path/path.dart' as p;
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

import '../data/write_back.dart';

/// Whether this platform's SQLite supports write-ahead logging.
const bool sqliteSupportsWal = true;

/// Opens (creating if needed) database [name] inside [directory]. Writes
/// are synchronous, so nothing is added to [writes].
Future<CommonDatabase> openSqlite({
  required String name,
  required String directory,
  StorageWrites? writes,
}) async => sqlite3.open(p.join(directory, name));

/// A private in-memory database (tests).
CommonDatabase openSqliteInMemory() => sqlite3.openInMemory();

/// Opens (creating if needed) the database file at [path].
CommonDatabase openSqliteFile(String path) => sqlite3.open(path);

/// The file [openSqlite] opens for [name] in [directory].
String? sqliteFilePath({required String name, required String directory}) =>
    p.join(directory, name);

/// A private in-memory database that also works in browsers (scratch
/// surfaces such as the Ink Lab's).
Future<CommonDatabase> openSqliteScratch() async => sqlite3.openInMemory();

/// Makes [db]'s writes wait up to [timeoutMs] for another connection's
/// transaction (a pull worker's) before failing with `SQLITE_BUSY`,
/// polling every millisecond or so.
///
/// Not `PRAGMA busy_timeout`: the bundled SQLite's default busy handler
/// does not sleep between its attempts (it gives up within ~70 ms whatever
/// the timeout), so a write failed whenever the other's transaction ran a
/// little long.
void waitWhenBusy(CommonDatabase db, int timeoutMs) {
  final waited = Stopwatch();
  db.busyHandler = (count) {
    if (count == 0) waited.reset();
    waited.start();
    if (waited.elapsedMilliseconds >= timeoutMs) return false;
    sleep(Duration(milliseconds: count < 20 ? 1 : 5));
    return true;
  };
}
