import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../data/write_back.dart';

/// Opens IndexedDB database [name] at [version], creating its stores in
/// [upgrade] when new.
Future<web.IDBDatabase> idbOpen(
  String name,
  int version,
  void Function(web.IDBDatabase db) upgrade,
) async {
  final request = web.window.indexedDB.open(name, version);
  request.onupgradeneeded = ((web.Event _) => upgrade(request.result as web.IDBDatabase)).toJS;
  return (await idbResult(request)) as web.IDBDatabase;
}

/// The result of [request] once it succeeds.
Future<JSAny?> idbResult(web.IDBRequest request) {
  final done = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) => done.complete(request.result)).toJS;
  request.onerror = ((web.Event _) {
    if (!done.isCompleted) done.completeError(idbError(request.error, 'IndexedDB request failed'));
  }).toJS;
  return done.future;
}

/// Completes when [transaction] has been committed; throws
/// [StorageFullException] if it failed for lack of space.
Future<void> idbCompletion(web.IDBTransaction transaction) {
  final done = Completer<void>();
  transaction.oncomplete = ((web.Event _) {
    if (!done.isCompleted) done.complete();
  }).toJS;
  void fail(web.Event _) {
    if (!done.isCompleted) {
      done.completeError(idbError(transaction.error, 'IndexedDB write failed'));
    }
  }

  transaction.onerror = fail.toJS;
  transaction.onabort = fail.toJS;
  return done.future;
}

/// The Dart exception for an IndexedDB [error].
Object idbError(web.DOMException? error, String what) {
  if (error?.name == 'QuotaExceededError') return StorageFullException('$what: ${error?.message}');
  return StateError('$what: ${error?.name} ${error?.message}');
}
