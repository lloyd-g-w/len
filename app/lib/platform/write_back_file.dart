part of 'write_back_vfs.dart';

/// Copies [file] from [offset] into [target], as much as there is; returns
/// how many bytes. Only that range is handed to [target]: with dart2wasm,
/// [target] is a view of SQLite's wasm memory, whose `setRange` from a Dart
/// list copied the whole rest of the list first (`skip(offset).toList()`),
/// which made every page read cost the size of the database (a restore of
/// 20 MB took minutes).
@visibleForTesting
int readFileRange(Uint8List file, Uint8List target, int offset) {
  if (offset >= file.length) return 0;
  final count = min(target.length, file.length - offset);
  target.setRange(0, count, Uint8List.sublistView(file, offset, offset + count));
  return count;
}

class _WriteBackFile implements VirtualFileSystemFileV1 {
  _WriteBackFile(this._fs, this._file, this._path);

  final WriteBackFileSystem _fs;
  final VirtualFileSystemFileV1 _file;
  final String _path;

  bool get _stored => !_fs._memoryOnly.contains(_path);

  @override
  void xRead(Uint8List target, int fileOffset) {
    final data = _fs._memory.fileData[_path];
    final read = data == null
        ? 0
        : readFileRange(data.buffer.asUint8List(0, data.length), target, fileOffset);
    if (read < target.length) {
      target.fillRange(read, target.length, 0);
      throw const VfsException(SqlExtendedError.SQLITE_IOERR_SHORT_READ);
    }
  }

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
