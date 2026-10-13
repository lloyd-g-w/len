import 'dart:async';

import 'package:flutter/foundation.dart';

import 'blob_backend.dart';
import 'write_back.dart';

/// Keeps blobs that [inner] failed to store (a full browser storage) in
/// memory and retries storing them, so a failed write never loses a file:
/// it stays readable here until it is stored. Also counts writes in
/// progress as [pending], so a tab hand-over waits for them.
class WriteBackBlobBackend with ChangeNotifier implements BlobBackend, WriteBackStore {
  WriteBackBlobBackend(this._inner);

  final BlobBackend _inner;

  /// Blobs not stored yet: being written, or waiting for a retry.
  final Map<String, Uint8List> _unstored = {};
  int _writing = 0;
  WriteFailure? _failure;
  late final WriteBackRetry _retry = WriteBackRetry(() => unawaited(flush()));
  Future<bool>? _flushing;
  bool _closed = false;

  @override
  bool get pending => _unstored.isNotEmpty;

  @override
  WriteFailure? get failure => _failure;

  @override
  Future<bool> contains(String sha) async =>
      _unstored.containsKey(sha) || await _inner.contains(sha);

  @override
  Future<Uint8List?> read(String sha) async => _unstored[sha] ?? await _inner.read(sha);

  @override
  Stream<List<int>> openRead(String sha) {
    final bytes = _unstored[sha];
    return bytes == null ? _inner.openRead(sha) : Stream.value(bytes);
  }

  /// Completes once the blob is stored or, if storing fails, kept in
  /// memory for a retry (the failure is reported through [failure]).
  @override
  Future<void> write(String sha, Stream<List<int>> data) async {
    if (_closed) throw StateError('Blob storage is closed');
    final bytes = await collectBytes(data);
    _unstored[sha] = bytes;
    _writing++;
    notifyListeners();
    try {
      await _store(sha, bytes);
    } finally {
      _writing--;
    }
  }

  /// Stores [sha]; on failure keeps it and schedules a retry. Returns
  /// whether it is stored.
  Future<bool> _store(String sha, Uint8List bytes) async {
    try {
      await _inner.write(sha, Stream.value(bytes));
    } on Object catch (error) {
      debugPrint('Storing blob $sha failed: $error');
      _failure = writeFailureOf(error);
      _retry.failed();
      notifyListeners();
      return false;
    }
    if (identical(_unstored[sha], bytes)) _unstored.remove(sha);
    if (_unstored.length == _writing) {
      _failure = null;
      _retry.succeeded();
    }
    notifyListeners();
    return true;
  }

  @override
  Future<bool> flush() => _flushing ??= _flushAll().whenComplete(() => _flushing = null);

  Future<bool> _flushAll() async {
    var stored = true;
    for (final MapEntry(:key, :value) in Map.of(_unstored).entries) {
      stored = await _store(key, value) && stored;
    }
    return stored;
  }

  @override
  Future<bool> close() {
    _closed = true;
    return flush();
  }

  @override
  Future<void> delete(String sha) async {
    if (_closed) throw StateError('Blob storage is closed');
    _unstored.remove(sha);
    await _inner.delete(sha);
    if (_unstored.isEmpty && _failure != null) {
      _failure = null;
      _retry.succeeded();
    }
    notifyListeners();
  }

  @override
  String? localPath(String sha) => null;
}
