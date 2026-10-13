import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/common.dart';

import '../data/write_back.dart';

/// Size of the blocks files are stored in.
const writeBackBlockSize = 4096;

/// Durable storage for [WriteBackFileSystem]: files as blocks of
/// [writeBackBlockSize] bytes (IndexedDB on the web; fakes in tests).
abstract interface class BlockStore {
  /// Every stored file's content.
  Future<Map<String, Uint8List>> readAll();

  /// Applies [changes] atomically: all of them or (throwing) none.
  /// Throws [StorageFullException] when out of space.
  Future<void> commit(List<FileChange> changes);

  void close();
}

/// A change to one stored file.
class FileChange {
  const FileChange.delete(this.path) : length = null, blocks = const {}, replace = false;

  const FileChange.write(
    this.path, {
    required int this.length,
    required this.blocks,
    this.replace = false,
  });

  final String path;

  /// The file's new length; null if the file is deleted.
  final int? length;

  /// New content of the blocks that changed, by offset; each block is
  /// [writeBackBlockSize] long (zero-padded past [length]).
  final Map<int, Uint8List> blocks;

  /// Whether every other stored block of the file is dropped (a new file).
  final bool replace;

  bool get deleted => length == null;
}

/// What changed in a file since it was last stored.
class _Dirty {
  bool deleted = false;
  bool replace = false;
  final Set<int> blocks = {};

  /// Merges [older] changes that failed to be stored (this one is newer).
  void mergeOlder(_Dirty older) {
    if (deleted) return; // Deleted since: nothing older matters.
    replace |= older.replace;
    if (!older.deleted) blocks.addAll(older.blocks);
  }
}

/// A SQLite file system kept in memory and written back to a [BlockStore]
/// right after each change (the next event-loop turn), only between
/// transactions, so the stored database is always consistent. Failed
/// writes are kept as dirty blocks and retried ([WriteBackRetry]): the
/// in-memory database stays usable and nothing is dropped.
final class WriteBackFileSystem extends BaseVirtualFileSystem
    with ChangeNotifier
    implements WriteBackStore {
  WriteBackFileSystem._(this._store, {required super.name}) : super();

  /// Loads every file of [store] into memory.
  static Future<WriteBackFileSystem> open(BlockStore store, {String name = 'len-idb'}) async {
    final fs = WriteBackFileSystem._(store, name: name);
    for (final MapEntry(:key, :value) in (await store.readAll()).entries) {
      final file = fs._memory.xOpen(Sqlite3Filename(key), SqlFlag.SQLITE_OPEN_CREATE).file;
      file.xWrite(value, 0);
      file.xClose();
    }
    return fs;
  }

  final BlockStore _store;
  final InMemoryFileSystem _memory = InMemoryFileSystem();
  final Map<String, _Dirty> _dirty = {};

  /// Files never stored: temporary ones and the rollback journal (stored
  /// files are only written between transactions, so it is never needed).
  final Set<String> _memoryOnly = {};

  late final WriteBackRetry _retry = WriteBackRetry(() async {
    if (await flush() && _closed) _store.close();
  });
  Future<bool>? _writing;
  bool _scheduled = false;
  bool _closed = false;
  WriteFailure? _failure;

  @override
  bool get pending => _dirty.isNotEmpty || _writing != null;

  @override
  WriteFailure? get failure => _failure;

  /// Whether a write transaction is open (its journal exists).
  bool get _inTransaction => _memory.fileData.keys.any((p) => p.endsWith('-journal'));

  _Dirty _mark(String path) {
    final wasPending = pending;
    final dirty = _dirty.putIfAbsent(path, _Dirty.new);
    // Not from inside SQLite's call: a listener might use the database.
    if (!wasPending) scheduleMicrotask(notifyListeners);
    _flushSoon();
    return dirty;
  }

  void _flushSoon() {
    if (_scheduled || _closed) return;
    _scheduled = true;
    // After the current synchronous work (a whole transaction); a timer
    // would be throttled in background tabs.
    scheduleMicrotask(() {
      _scheduled = false;
      unawaited(flush());
    });
  }

  @override
  Future<bool> flush() async {
    // Wait for the write in progress, then write what changed meanwhile.
    while (_writing != null) {
      if (!await _writing!) return false;
    }
    if (_dirty.isEmpty) return true;
    if (_inTransaction) return false; // Written when the transaction ends.
    final writing = _write();
    _writing = writing;
    try {
      return await writing;
    } finally {
      _writing = null;
      notifyListeners();
    }
  }

  Future<bool> _write() async {
    final snapshot = Map.of(_dirty);
    _dirty.clear();
    final changes = [for (final e in snapshot.entries) _changeOf(e.key, e.value)];
    try {
      await _store.commit(changes);
      _retry.succeeded();
      _failure = null;
      return true;
    } on Object catch (error) {
      debugPrint('Storing the database failed: $error');
      for (final MapEntry(:key, :value) in snapshot.entries) {
        final newer = _dirty[key];
        if (newer == null) {
          _dirty[key] = value;
        } else {
          newer.mergeOlder(value);
        }
      }
      _failure = writeFailureOf(error);
      _retry.failed();
      return false;
    }
  }

  FileChange _changeOf(String path, _Dirty dirty) {
    final data = _memory.fileData[path];
    if (dirty.deleted || data == null) return FileChange.delete(path);
    final length = data.length;
    final bytes = data.buffer.asUint8List(0, length);
    final offsets = dirty.replace
        ? [for (var o = 0; o < length; o += writeBackBlockSize) o]
        : dirty.blocks.where((o) => o < length);
    return FileChange.write(
      path,
      length: length,
      replace: dirty.replace,
      blocks: {
        for (final o in offsets)
          o: Uint8List(writeBackBlockSize)
            ..setRange(0, min(writeBackBlockSize, length - o), bytes, o),
      },
    );
  }

  /// Stops writing: later changes fail (SQLite I/O errors), and the store
  /// closes once everything is stored.
  @override
  Future<bool> close() async {
    _closed = true;
    _retry.cancel();
    final stored = await flush();
    if (stored) {
      _store.close();
    } else {
      _retry.failed(); // Keep trying until it is stored, then close.
    }
    return stored;
  }

  void _checkOpen() {
    if (_closed) throw const VfsException(SqlError.SQLITE_IOERR);
  }

  @override
  int xAccess(String path, int flags) => _memory.xAccess(path, flags);

  @override
  void xDelete(String path, int syncDir) {
    if (_memoryOnly.remove(path)) {
      _memory.xDelete(path, syncDir);
      if (path.endsWith('-journal')) _flushSoon(); // The transaction ended.
      return;
    }
    _checkOpen();
    _memory.xDelete(path, syncDir);
    _mark(path)
      ..deleted = true
      ..replace = false
      ..blocks.clear();
  }

  @override
  String xFullPathName(String path) => _memory.xFullPathName(path);

  @override
  XOpenResult xOpen(Sqlite3Filename path, int flags) {
    final name = path.path ?? random.nextInt(1 << 30).toString();
    final existed = _memory.xAccess(name, 0) != 0;
    final file = _memory.xOpen(Sqlite3Filename(name), flags).file;
    if (!existed) {
      if (flags & SqlFlag.SQLITE_OPEN_DELETEONCLOSE != 0 || name.endsWith('-journal')) {
        _memoryOnly.add(name);
      } else {
        _checkOpen();
        _mark(name)
          ..deleted = false
          ..replace = true;
      }
    }
    return (outFlags: 0, file: _WriteBackFile(this, file as VirtualFileSystemFileV1, name));
  }

  @override
  void xSleep(Duration duration) {}

  void _written(String path, int offset, int length) {
    if (_memoryOnly.contains(path)) return;
    final dirty = _mark(path);
    for (
      var o = offset - offset % writeBackBlockSize;
      o < offset + length;
      o += writeBackBlockSize
    ) {
      dirty.blocks.add(o);
    }
  }

  void _truncated(String path) {
    if (!_memoryOnly.contains(path)) _mark(path);
  }
}

class _WriteBackFile implements VirtualFileSystemFileV1 {
  _WriteBackFile(this._fs, this._file, this._path);

  final WriteBackFileSystem _fs;
  final VirtualFileSystemFileV1 _file;
  final String _path;

  bool get _stored => !_fs._memoryOnly.contains(_path);

  @override
  void xRead(Uint8List target, int fileOffset) => _file.xRead(target, fileOffset);

  @override
  void xWrite(Uint8List buffer, int fileOffset) {
    if (_stored) _fs._checkOpen();
    _file.xWrite(buffer, fileOffset);
    _fs._written(_path, fileOffset, buffer.length);
  }

  @override
  void xTruncate(int size) {
    if (_stored) _fs._checkOpen();
    _file.xTruncate(size);
    _fs._truncated(_path);
  }

  @override
  void xClose() {
    _file.xClose(); // Deletes a delete-on-close file from memory.
    if (_fs._memory.xAccess(_path, 0) == 0) _fs._memoryOnly.remove(_path);
  }

  @override
  void xSync(int flags) {}

  @override
  int xFileSize() => _file.xFileSize();

  @override
  void xLock(int mode) => _file.xLock(mode);

  @override
  void xUnlock(int mode) => _file.xUnlock(mode);

  @override
  int xCheckReservedLock() => _file.xCheckReservedLock();

  @override
  int get xDeviceCharacteristics => 0;

  @override
  int xFileControl(int op, int ptr) => SqlError.SQLITE_NOTFOUND;

  @override
  int get xSectorSize => writeBackBlockSize;
}
