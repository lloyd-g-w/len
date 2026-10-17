import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/common.dart' show Row;

import '../core/clock.dart';
import '../domain/cancellation.dart';
import 'app_database.dart';
import 'blob_backend.dart';
import 'blob_mime.dart';
import 'freed_blobs.dart';

part 'blob_store_cleanup.dart';

/// Content-addressed storage for large binary data (PDFs, later images).
///
/// A blob is identified by the SHA-256 of its bytes (lowercase hex), so it
/// is immutable and identical on every device. The bytes live in a
/// [BlobBackend] (files natively, IndexedDB on the web); the `blobs` table
/// records which blobs are present and whether they have been uploaded to
/// the sync server yet.
class BlobStore with _BlobCleanup {
  BlobStore(this.database, this.backend, {this.clock = const Clock()})
    : freed = FreedBlobs(database);

  @override
  final AppDatabase database;
  @override
  final BlobBackend backend;
  @override
  final Clock clock;

  /// Files whose copies here [removeLocalCopies] removed.
  @override
  final FreedBlobs freed;

  /// How long a blob stays after the last live row referencing it is gone.
  static const gcGrace = Duration(days: 7);

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

  /// The blob's MIME type as stored, or `application/octet-stream`.
  String mimeOf(String sha) =>
      database.db.select('SELECT mime FROM blobs WHERE sha256 = ?', [sha]).firstOrNull?['mime']
          as String? ??
      'application/octet-stream';

  /// The file holding the blob on platforms with files, else null. Lets
  /// large PDFs be opened without reading them into memory.
  String? localPath(String sha) => backend.localPath(_checked(sha));

  /// Stores [bytes] (a no-op if already present) and returns their id.
  /// Small blobs (version packs and tables) are hashed here: quicker than
  /// starting an isolate; large ones in one.
  Future<String> putBytes(Uint8List bytes, {required String mime}) async {
    final sha = bytes.length <= inlineHashBytes
        ? _sha256Hex(bytes)
        : await compute(_sha256Hex, bytes);
    return _exclusive(() async {
      if (!await has(sha)) await backend.write(sha, Stream.value(bytes));
      _record(sha, bytes.length, mime, uploaded: false);
      return sha;
    });
  }

  /// Blobs up to this size are hashed without an isolate.
  static const inlineHashBytes = 64 * 1024;

  /// Stores a copy of [source] (e.g. a picked file; streamed where the
  /// platform allows) and returns its id. A [cancel]led token stops it
  /// (with [Cancelled]) while reading or storing; nothing is stored then
  /// (writes are atomic).
  Future<String> putFile(XFile source, {required String mime, CancellationToken? cancel}) async {
    Stream<List<int>> read() => cancel?.guard(source.openRead()) ?? source.openRead();
    final sha = await hashStream(read());
    cancel?.check();
    return _exclusive(() async {
      cancel?.check();
      if (!await has(sha)) await backend.write(sha, read());
      _record(sha, await source.length(), mime, uploaded: false);
      return sha;
    });
  }

  /// Stores blob [sha] from [open] (called once to check the bytes hash to
  /// [sha], once more to store them; e.g. a Len file's entry) and returns
  /// whether it was new here. Throws [FormatException] if the bytes don't
  /// match, before anything is stored.
  Future<bool> putVerified(
    String sha,
    Stream<List<int>> Function() open, {
    required String mime,
  }) async {
    _checked(sha);
    if (await _exclusive(() => _keepIfPresent(sha))) return false;
    var size = 0;
    final actual = await hashStream(
      open().map((chunk) {
        size += chunk.length;
        return chunk;
      }),
    );
    if (actual != sha) throw FormatException('Blob $sha is damaged');
    return _exclusive(() async {
      if (await _keepIfPresent(sha)) return false;
      if (!await backend.contains(sha)) await backend.write(sha, open());
      _record(sha, size, mime, uploaded: false);
      return true;
    });
  }

  /// Whether blob [sha] is here; if so it counts as stored again (its
  /// grace period restarts, as with the other `put`s).
  Future<bool> _keepIfPresent(String sha) async {
    if (!await has(sha)) return false;
    _setUnreferencedSince(sha, null);
    return true;
  }

  /// Stores a blob fetched from the sync server after checking its hash.
  /// Throws [FormatException] if the bytes do not match [sha]. It counts as
  /// uploaded (the server has it) if [fromCurrentServer] still says so once
  /// it is stored: a download from a server this device has since left
  /// must still be uploaded to the new one. Its MIME type is told by its
  /// content ([BlobMime]).
  Future<void> putDownloaded(
    String sha,
    Uint8List bytes, {
    bool Function()? fromCurrentServer,
  }) async {
    final actual = await compute(_sha256Hex, bytes);
    if (actual != sha) throw FormatException('Blob $sha arrived corrupted');
    await _exclusive(() async {
      if (!await backend.contains(sha)) await backend.write(sha, Stream.value(bytes));
      _record(
        sha,
        bytes.length,
        BlobMime.sniff(bytes),
        uploaded: fromCurrentServer?.call() ?? true,
      );
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

  @override
  void _setUnreferencedSince(String sha, int? ms) =>
      database.db.execute('UPDATE blobs SET unreferenced_since = ? WHERE sha256 = ?', [ms, sha]);

  /// Completes when the last exclusive action has; null when idle.
  Future<void>? _tail;

  /// Runs [action] after every earlier exclusive action has finished (right
  /// away when none is running, so no future outlives its zone, e.g. in
  /// tests with fake time).
  @override
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final previous = _tail;
    final result = previous == null ? action() : previous.then((_) => action());
    final tail = result.then<void>((_) {}, onError: (Object _) {});
    _tail = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_tail, tail)) _tail = null;
      }),
    );
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

  @override
  bool _isRecorded(String sha) =>
      database.db.select('SELECT 1 FROM blobs WHERE sha256 = ?', [sha]).isNotEmpty;

  static String _checked(String sha) {
    if (!isValidId(sha)) throw ArgumentError.value(sha, 'sha', 'not a SHA-256 hex digest');
    return sha;
  }

  /// Records a stored blob. A blob stored again counts as freshly used, so
  /// garbage collection restarts its grace period.
  void _record(String sha, int size, String mime, {required bool uploaded}) {
    freed.remove(sha);
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
