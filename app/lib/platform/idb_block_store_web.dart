import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'idb_web.dart';
import 'write_back_vfs.dart';

// The layout of package:sqlite3's IndexedDbFileSystem (which Len used
// before), so existing browser data opens: store `files` (auto-increment
// keys, `{name, length}`, unique index `fileName` on `name`) and store
// `blocks` (key `[fileId, offset]`, a 4096-byte ArrayBuffer).
const _files = 'files';
const _blocks = 'blocks';
const _maxOffset = 9007199254740992; // 2^53: past any file's end.

/// A [BlockStore] in IndexedDB database [name]. Each commit is one
/// transaction, so the stored database is never half-written.
class IdbBlockStore implements BlockStore {
  IdbBlockStore._(this._db);

  /// Opens (creating if needed) IndexedDB database [name].
  static Future<IdbBlockStore> open(String name) async => IdbBlockStore._(
    await idbOpen(name, 1, (db) {
      db
          .createObjectStore(_files, web.IDBObjectStoreParameters(autoIncrement: true))
          .createIndex('fileName', 'name'.toJS, web.IDBIndexParameters(unique: true));
      db.createObjectStore(_blocks);
    }),
  );

  final web.IDBDatabase _db;

  /// File ids by path, as stored.
  final Map<String, int> _ids = {};

  @override
  Future<Map<String, Uint8List>> readAll() async {
    final tx = _db.transaction([_files.toJS, _blocks.toJS].toJS, 'readonly');
    final files = tx.objectStore(_files);
    final blocks = tx.objectStore(_blocks);
    final results = await Future.wait([
      idbResult(files.getAllKeys()),
      idbResult(files.getAll()),
      idbResult(blocks.getAllKeys()),
      idbResult(blocks.getAll()),
    ]);
    final fileKeys = (results[0] as JSArray<JSNumber>).toDart;
    final fileValues = (results[1] as JSArray<JSObject>).toDart;
    final byId = <int, Uint8List>{};
    for (var i = 0; i < fileKeys.length; i++) {
      final entry = fileValues[i] as _FileEntry;
      final id = fileKeys[i].toDartInt;
      _ids[entry.name] = id;
      byId[id] = Uint8List(entry.length);
    }
    final blockKeys = (results[2] as JSArray<JSArray<JSNumber>>).toDart;
    final blockValues = (results[3] as JSArray<JSAny>).toDart;
    for (var i = 0; i < blockKeys.length; i++) {
      final key = blockKeys[i].toDart;
      final file = byId[key[0].toDartInt];
      final offset = key[1].toDartInt;
      if (file == null || offset >= file.length) continue;
      final value = blockValues[i];
      final bytes = value.isA<web.Blob>()
          ? (await (value as web.Blob).arrayBuffer().toDart).toDart.asUint8List()
          : (value as JSArrayBuffer).toDart.asUint8List();
      final length = file.length - offset < bytes.length ? file.length - offset : bytes.length;
      file.setRange(offset, offset + length, bytes);
    }
    return {for (final MapEntry(:key, :value) in _ids.entries) key: byId[value]!};
  }

  @override
  Future<void> commit(List<FileChange> changes) async {
    final tx = _db.transaction([_files.toJS, _blocks.toJS].toJS, 'readwrite');
    final files = tx.objectStore(_files);
    final blocks = tx.objectStore(_blocks);
    final ids = Map.of(_ids);
    var nextId = ids.values.fold(0, (a, b) => a > b ? a : b) + 1;
    for (final change in changes) {
      var id = ids[change.path];
      if (change.deleted) {
        if (id == null) continue;
        blocks.delete(_range(id, 0));
        files.delete(id.toJS);
        ids.remove(change.path);
        continue;
      }
      if (id == null) {
        id = ids[change.path] = nextId++;
      } else if (change.replace) {
        blocks.delete(_range(id, 0));
      }
      final length = change.length!;
      final end = (length + writeBackBlockSize - 1) ~/ writeBackBlockSize * writeBackBlockSize;
      blocks.delete(_range(id, end)); // Past the end (a truncated file).
      for (final MapEntry(key: offset, value: block) in change.blocks.entries) {
        blocks.put(block.buffer.toJS, [id.toJS, offset.toJS].toJS);
      }
      files.put(_FileEntry(name: change.path, length: length), id.toJS);
    }
    await idbCompletion(tx);
    _ids
      ..clear()
      ..addAll(ids);
  }

  web.IDBKeyRange _range(int id, int from) =>
      web.IDBKeyRange.bound([id.toJS, from.toJS].toJS, [id.toJS, _maxOffset.toJS].toJS);

  @override
  void close() => _db.close();
}

@JS()
extension type _FileEntry._(JSObject _) implements JSObject {
  external String get name;
  external int get length;

  external factory _FileEntry({required String name, required int length});
}
