import 'package:sqlite3/wasm.dart';

import '../data/write_back.dart';
import 'idb_block_store_web.dart';
import 'write_back_vfs.dart';

/// IndexedDB-backed VFS has no shared memory, so no WAL.
const bool sqliteSupportsWal = false;

/// SQLite compiled to WebAssembly (`web/sqlite3.wasm`), loaded once per
/// page and shared by every connection, with [_scratchFs] registered
/// (loaded again after a failure, by Try again).
Future<WasmSqlite3> _sqlite() => _loading ??= () async {
  try {
    return await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'))
      ..registerVirtualFileSystem(_scratchFs);
  } on Object {
    _loading = null;
    rethrow;
  }
}();
Future<WasmSqlite3>? _loading;

/// Holds nothing but the temporary files of in-memory databases.
final _scratchFs = InMemoryFileSystem(name: 'len-scratch');

/// The [WriteBackFileSystem] registered last (replaced when the storage is
/// opened again after a failed start).
WriteBackFileSystem? _storageFs;

/// Opens database [name] in the browser: SQLite on a [WriteBackFileSystem]
/// that keeps the database in memory and writes it back to IndexedDB
/// (database `len`) after each transaction; added to [writes], which tells
/// when that is done or failing. [directory] is ignored.
Future<CommonDatabase> openSqlite({
  required String name,
  required String directory,
  StorageWrites? writes,
}) async {
  final sqlite = await _sqlite();
  final fs = await WriteBackFileSystem.open(await IdbBlockStore.open('len'));
  if (_storageFs case final previous?) sqlite.unregisterVirtualFileSystem(previous);
  sqlite.registerVirtualFileSystem(_storageFs = fs, makeDefault: true);
  writes?.add(fs);
  return sqlite.open('/$name', vfs: fs.name);
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

/// A private in-memory database (the schema check's, scratch surfaces such
/// as the Ink Lab's) on the shared SQLite with an in-memory file system, so
/// nothing reaches IndexedDB.
Future<CommonDatabase> openSqliteScratch() async =>
    (await _sqlite()).openInMemory(vfs: _scratchFs.name);

/// Browsers have one connection per database: nothing waits for another.
void waitWhenBusy(CommonDatabase db, int timeoutMs) {}
