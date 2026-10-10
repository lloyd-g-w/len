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
    if (!await has(sha)) {
      await backend.write(sha, Stream.value(bytes));
      _record(sha, bytes.length, mime, uploaded: false);
    }
    return sha;
  }

  /// Stores a copy of [source] (e.g. a picked file; streamed where the
  /// platform allows) and returns its id.
  Future<String> putFile(XFile source, {required String mime}) async {
    final sha = await hashStream(source.openRead());
    if (!await has(sha)) {
      await backend.write(sha, source.openRead());
      _record(sha, await source.length(), mime, uploaded: false);
    }
    return sha;
  }

  /// Stores a blob fetched from the sync server after checking its hash.
  /// Throws [FormatException] if the bytes do not match [sha].
  Future<void> putDownloaded(String sha, Uint8List bytes, {String mime = 'application/pdf'}) async {
    final actual = await compute(_sha256Hex, bytes);
    if (actual != sha) throw FormatException('Blob $sha arrived corrupted');
    if (!await backend.contains(sha)) await backend.write(sha, Stream.value(bytes));
    _record(sha, bytes.length, mime, uploaded: true);
  }

  /// Ids of local blobs the sync server does not have yet.
  List<String> pendingUploads() => database.db
      .select('SELECT sha256 FROM blobs WHERE uploaded = 0 ORDER BY created_at')
      .map((r) => r['sha256'] as String)
      .toList();

  void markUploaded(String sha) =>
      database.db.execute('UPDATE blobs SET uploaded = 1 WHERE sha256 = ?', [sha]);

  /// After switching servers, everything must be uploaded again.
  void markAllNotUploaded() => database.db.execute('UPDATE blobs SET uploaded = 0');

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

  void _record(String sha, int size, String mime, {required bool uploaded}) {
    database.db.execute(
      '''
      INSERT INTO blobs (sha256, size, mime, created_at, uploaded) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(sha256) DO UPDATE SET uploaded = MAX(uploaded, excluded.uploaded)''',
      [sha, size, mime, clock.nowMs(), uploaded ? 1 : 0],
    );
  }
}

String _sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();
