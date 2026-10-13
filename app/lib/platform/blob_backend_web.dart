import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../data/blob_backend.dart';
import '../data/write_back.dart';
import '../data/write_back_blobs.dart';
import 'idb_web.dart';

/// Opens the app's blob storage: an IndexedDB object store (database
/// `len_blobs`), separate from the SQLite database so large PDFs are not
/// part of the SQLite file the VFS keeps in memory. Blobs it fails to
/// store (storage full) wait in memory for a retry ([WriteBackBlobBackend],
/// added to [writes]). Falls back to memory ([VolatileBlobBackend]: blobs
/// then last until the tab closes, which the app tells the user) if
/// IndexedDB is unavailable. [directory] is ignored.
Future<BlobBackend> openBlobBackend(String directory, {StorageWrites? writes}) async {
  final web.IDBDatabase db;
  try {
    db = await idbOpen(_databaseName, 1, (db) => db.createObjectStore(_storeName));
  } on Object catch (e) {
    debugPrint('IndexedDB unavailable, keeping blobs in memory: $e');
    return VolatileBlobBackend();
  }
  final backend = WriteBackBlobBackend(IndexedDbBlobBackend._(db));
  writes?.add(backend);
  return backend;
}

const _databaseName = 'len_blobs';
const _storeName = 'blobs';

/// Stores each blob as a `Uint8Array` keyed by its SHA-256.
class IndexedDbBlobBackend implements BlobBackend {
  IndexedDbBlobBackend._(this._db);

  final web.IDBDatabase _db;

  web.IDBObjectStore _store(String mode) =>
      _db.transaction(_storeName.toJS, mode).objectStore(_storeName);

  @override
  Future<bool> contains(String sha) async {
    final count = await idbResult(_store('readonly').count(sha.toJS));
    return (count as JSNumber).toDartInt > 0;
  }

  @override
  Future<Uint8List?> read(String sha) async {
    final value = await idbResult(_store('readonly').get(sha.toJS));
    return value == null ? null : (value as JSUint8Array).toDart;
  }

  @override
  Stream<List<int>> openRead(String sha) async* {
    final bytes = await read(sha);
    if (bytes != null) yield bytes;
  }

  /// One IndexedDB transaction, so the write is atomic. Throws
  /// [StorageFullException] when the browser's quota is used up.
  @override
  Future<void> write(String sha, Stream<List<int>> data) async {
    final bytes = await collectBytes(data);
    final transaction = _db.transaction(_storeName.toJS, 'readwrite');
    transaction.objectStore(_storeName).put(bytes.toJS, sha.toJS);
    await idbCompletion(transaction);
  }

  @override
  Future<void> delete(String sha) async {
    final transaction = _db.transaction(_storeName.toJS, 'readwrite');
    transaction.objectStore(_storeName).delete(sha.toJS);
    await idbCompletion(transaction);
  }

  @override
  String? localPath(String sha) => null;
}
