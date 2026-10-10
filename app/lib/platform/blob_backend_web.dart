import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../data/blob_backend.dart';

/// Opens the app's blob storage: an IndexedDB object store (database
/// `len_blobs`), separate from the SQLite database so large PDFs are not
/// part of the SQLite file the wasm VFS keeps in memory. Falls back to
/// memory (blobs then last until the tab closes) if IndexedDB is
/// unavailable. [directory] is ignored.
Future<BlobBackend> openBlobBackend(String directory) async {
  try {
    return IndexedDbBlobBackend._(await _openDatabase());
  } on Object catch (e) {
    debugPrint('IndexedDB unavailable, keeping blobs in memory: $e');
    return MemoryBlobBackend();
  }
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
    final count = await _result(_store('readonly').count(sha.toJS));
    return (count as JSNumber).toDartInt > 0;
  }

  @override
  Future<Uint8List?> read(String sha) async {
    final value = await _result(_store('readonly').get(sha.toJS));
    return value == null ? null : (value as JSUint8Array).toDart;
  }

  @override
  Stream<List<int>> openRead(String sha) async* {
    final bytes = await read(sha);
    if (bytes != null) yield bytes;
  }

  /// One IndexedDB transaction, so the write is atomic.
  @override
  Future<void> write(String sha, Stream<List<int>> data) async {
    final bytes = await collectBytes(data);
    final transaction = _db.transaction(_storeName.toJS, 'readwrite');
    transaction.objectStore(_storeName).put(bytes.toJS, sha.toJS);
    await _completion(transaction);
  }

  @override
  String? localPath(String sha) => null;
}

Future<web.IDBDatabase> _openDatabase() async {
  final request = web.window.indexedDB.open(_databaseName, 1);
  request.onupgradeneeded = ((web.Event _) {
    (request.result as web.IDBDatabase).createObjectStore(_storeName);
  }).toJS;
  return (await _result(request)) as web.IDBDatabase;
}

/// The result of [request] once it succeeds.
Future<JSAny?> _result(web.IDBRequest request) {
  final done = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) => done.complete(request.result)).toJS;
  request.onerror = ((web.Event _) {
    done.completeError(StateError('IndexedDB request failed: ${request.error?.message}'));
  }).toJS;
  return done.future;
}

/// Completes when [transaction] has been committed.
Future<void> _completion(web.IDBTransaction transaction) {
  final done = Completer<void>();
  transaction.oncomplete = ((web.Event _) => done.complete()).toJS;
  void fail(web.Event _) {
    if (!done.isCompleted) {
      done.completeError(StateError('IndexedDB write failed: ${transaction.error?.message}'));
    }
  }

  transaction.onerror = fail.toJS;
  transaction.onabort = fail.toJS;
  return done.future;
}
