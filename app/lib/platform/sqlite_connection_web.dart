import 'package:sqlite3/wasm.dart';

/// IndexedDB-backed VFS has no shared memory, so no WAL.
const bool sqliteSupportsWal = false;

/// Opens database [name] in the browser: SQLite compiled to WebAssembly
/// (`web/sqlite3.wasm`) with an IndexedDB-backed virtual file system, so
/// data persists across reloads. [directory] is ignored.
Future<CommonDatabase> openSqlite({required String name, required String directory}) async {
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  final fs = await IndexedDbFileSystem.open(dbName: 'len');
  sqlite.registerVirtualFileSystem(fs, makeDefault: true);
  return sqlite.open('/$name');
}

/// In-memory databases need the wasm module loaded asynchronously, which a
/// synchronous call cannot do; tests run on the VM instead.
CommonDatabase openSqliteInMemory() =>
    throw UnsupportedError('Synchronous in-memory SQLite is not available on the web');

/// Browsers have no file paths; use [openSqlite].
CommonDatabase openSqliteFile(String path) =>
    throw UnsupportedError('Opening database files by path is not available on the web');

/// Browser databases are not files.
String? sqliteFilePath({required String name, required String directory}) => null;
