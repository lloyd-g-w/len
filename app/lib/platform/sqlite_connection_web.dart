import 'package:sqlite3/wasm.dart';

import '../data/write_back.dart';
import 'idb_block_store_web.dart';
import 'write_back_vfs.dart';

/// IndexedDB-backed VFS has no shared memory, so no WAL.
const bool sqliteSupportsWal = false;

/// Opens database [name] in the browser: SQLite compiled to WebAssembly
/// (`web/sqlite3.wasm`) on a [WriteBackFileSystem] that keeps the database
/// in memory and writes it back to IndexedDB (database `len`) after each
/// transaction; added to [writes], which tells when that is done or
/// failing. [directory] is ignored.
Future<CommonDatabase> openSqlite({
  required String name,
  required String directory,
  StorageWrites? writes,
}) async {
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  final fs = await WriteBackFileSystem.open(await IdbBlockStore.open('len'));
  sqlite.registerVirtualFileSystem(fs, makeDefault: true);
  writes?.add(fs);
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

/// A private in-memory database (scratch surfaces such as the Ink Lab's):
/// its own WebAssembly instance with an in-memory file system, so nothing
/// reaches IndexedDB.
Future<CommonDatabase> openSqliteScratch() async {
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
  return sqlite.openInMemory();
}
