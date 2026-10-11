import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import 'app_database.dart';
import 'blob_backend.dart';

/// Content-addressed storage for large binary data (PDFs, later images).
///
/// A blob is identified by the SHA-256 of its bytes (lowercase hex), so it
/// is immutable and identical on every device. The bytes live in a
/// [BlobBackend] (files natively, IndexedDB on the web); the `blobs` table
/// records which blobs are present and whether they have been uploaded to
/// the sync server yet.
class BlobStore {
  BlobStore(this.database, this.backend, {this.clock = const Clock()});

  final AppDatabase database;
  final BlobBackend backend;
  final Clock clock;

  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  /// Whether [id] looks like a blob id.
  static bool isValidId(String id) => _sha256.hasMatch(id);

  /// Whether the blob is available locally.
  Future<bool> has(String sha) async =>
      isValidId(sha) && _isRecorded(sha) && await backend.contains(sha);

  /// The blob's bytes, or null if it is not available locally.
  Future<Uint8List?> read(String sha) async => await has(sha) ? backend.read(sha) : null;

  /// The blob's bytes in chunks; empty if it is not available locally.
  Stream<List<int>> openRead(String sha) => backend.openRead(_checked(sha));

  /// The blob's size in bytes, or null if it is not recorded.
  int? sizeOf(String sha) =>
      database.db.select('SELECT size FROM blobs WHERE sha256 = ?', [sha]).firstOrNull?['size']
          as int?;

  /// The file holding the blob on platforms with files, else null. Lets
  /// large PDFs be opened without reading them into memory.
  String? localPath(String sha) => backend.localPath(_checked(sha));

  /// Stores [bytes] (a no-op if already present) and returns their id.
  Future<String> putBytes(Uint8List bytes, {required String mime}) async {
    final sha = await compute(_sha256Hex, bytes);
    return _exclusive(() async {
      if (!await has(sha)) await backend.write(sha, Stream.value(bytes));
      _record(sha, bytes.length, mime, uploaded: false);
      return sha;
    });
  }

  /// Stores a copy of [source] (e.g. a picked file; streamed where the
  /// platform allows) and returns its id.
  Future<String> putFile(XFile source, {required String mime}) async {
    final sha = await hashStream(source.openRead());
    return _exclusive(() async {
      if (!await has(sha)) await backend.write(sha, source.openRead());
      _record(sha, await source.length(), mime, uploaded: false);
      return sha;
    });
  }

  /// Stores a blob fetched from the sync server after checking its hash.
  /// Throws [FormatException] if the bytes do not match [sha].
  Future<void> putDownloaded(String sha, Uint8List bytes, {String mime = 'application/pdf'}) async {
    final actual = await compute(_sha256Hex, bytes);
    if (actual != sha) throw FormatException('Blob $sha arrived corrupted');
    await _exclusive(() async {
      if (!await backend.contains(sha)) await backend.write(sha, Stream.value(bytes));
      _record(sha, bytes.length, mime, uploaded: true);
    });
  }

  /// Ids of local blobs the sync server does not have yet, except those it
  /// refused as too large.
  List<String> pendingUploads() => database.db
      .select(
        'SELECT sha256 FROM blobs WHERE uploaded = 0 AND rejected_limit IS NULL '
        'ORDER BY created_at',
      )
      .map((r) => r['sha256'] as String)
      .toList();

  void markUploaded(String sha) =>
      database.db.execute('UPDATE blobs SET uploaded = 1 WHERE sha256 = ?', [sha]);

  /// After switching servers, everything must be uploaded again (and the
  /// new server may accept larger blobs).
  void markAllNotUploaded() =>
      database.db.execute('UPDATE blobs SET uploaded = 0, rejected_limit = NULL');

  /// After the server deleted blobs (garbage collection), every upload is
  /// checked again; blobs refused as too large stay skipped.
  void recheckUploads() => database.db.execute('UPDATE blobs SET uploaded = 0');

  // ---------------------------------------------------------------------------
  // Garbage collection

  /// How long a blob stays after the last live row referencing it is gone.
  static const gcGrace = Duration(days: 7);

  /// Deletes blobs that [referenced] (the ids live rows reference) has not
  /// contained for [grace], counted from the first run that found them
  /// unreferenced, and returns their ids. Upload state does not matter: an
  /// unreferenced blob is never uploaded. Runs exclusively with the `put`
  /// methods, and storing a blob again restarts its grace period, so a blob
  /// being (re)imported is never deleted underneath its new reference.
  Future<List<String>> collectGarbage(
    Set<String> Function() referenced, {
    Duration grace = gcGrace,
  }) => _exclusive(() async {
    final now = clock.nowMs();
    final live = referenced();
    final due = <String>[];
    database.transaction(() {
      for (final row in database.db.select('SELECT sha256, unreferenced_since FROM blobs')) {
        final sha = row['sha256'] as String;
        final since = row['unreferenced_since'] as int?;
        if (live.contains(sha)) {
          if (since != null) _setUnreferencedSince(sha, null);
        } else if (since == null) {
          _setUnreferencedSince(sha, now);
        } else if (now - since >= grace.inMilliseconds) {
          due.add(sha);
        }
      }
    });
    for (final sha in due) {
      await backend.delete(sha);
      database.db.execute('DELETE FROM blobs WHERE sha256 = ?', [sha]);
    }
    return due;
  });

  void _setUnreferencedSince(String sha, int? ms) =>
      database.db.execute('UPDATE blobs SET unreferenced_since = ? WHERE sha256 = ?', [ms, sha]);

  Future<void> _queue = Future.value();

  /// Runs [action] after every earlier exclusive action has finished.
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  // ---------------------------------------------------------------------------
  // Blobs too large for the server

  /// Records that the server refuses blob [sha] as too large; [limit] is
  /// the server's advertised limit (null if unknown). It is skipped by
  /// [pendingUploads] until [retryTooLarge].
  void markTooLarge(String sha, int? limit) => database.db.execute(
    'UPDATE blobs SET rejected_limit = ? WHERE sha256 = ?',
    [limit ?? 0, sha],
  );

  /// Blobs refused as too large, with their sizes.
  List<({String sha, int size})> tooLarge() => [
    for (final r in database.db.select(
      'SELECT sha256, size FROM blobs WHERE rejected_limit IS NOT NULL ORDER BY created_at',
    ))
      (sha: r['sha256'] as String, size: r['size'] as int),
  ];

  /// Makes blobs refused as too large pending again: all of them, or with
  /// [newLimit] only those that fit it and were refused under a smaller
  /// limit (so a raised server limit is noticed, while a proxy refusing
  /// blobs below the server's limit does not cause a retry every sync).
  void retryTooLarge({int? newLimit}) => newLimit == null
      ? database.db.execute('UPDATE blobs SET rejected_limit = NULL')
      : database.db.execute(
          'UPDATE blobs SET rejected_limit = NULL '
          'WHERE rejected_limit IS NOT NULL AND rejected_limit < ? AND size <= ?',
          [newLimit, newLimit],
        );

  /// The SHA-256 of a byte stream, consumed in chunks.
  static Future<String> hashStream(Stream<List<int>> data) async {
    final digest = Completer<Digest>();
    final sink = sha256.startChunkedConversion(
      ChunkedConversionSink<Digest>.withCallback((d) => digest.complete(d.single)),
    );
    await data.forEach(sink.add);
    sink.close();
    return (await digest.future).toString();
  }

  bool _isRecorded(String sha) =>
      database.db.select('SELECT 1 FROM blobs WHERE sha256 = ?', [sha]).isNotEmpty;

  static String _checked(String sha) {
    if (!isValidId(sha)) throw ArgumentError.value(sha, 'sha', 'not a SHA-256 hex digest');
    return sha;
  }

  /// Records a stored blob. A blob stored again counts as freshly used, so
  /// garbage collection restarts its grace period.
  void _record(String sha, int size, String mime, {required bool uploaded}) {
    database.db.execute(
      '''
      INSERT INTO blobs (sha256, size, mime, created_at, uploaded) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(sha256) DO UPDATE SET uploaded = MAX(uploaded, excluded.uploaded),
        unreferenced_since = NULL''',
      [sha, size, mime, clock.nowMs(), uploaded ? 1 : 0],
    );
  }
}

String _sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();
