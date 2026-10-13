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
