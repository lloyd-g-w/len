import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/clock.dart';
import 'app_database.dart';

/// Content-addressed storage for large binary data (PDFs, later images).
///
/// A blob is identified by the SHA-256 of its bytes (lowercase hex), so it
/// is immutable and identical on every device. Files live in [directory]
/// (`<sha[0..2]>/<sha>`); the `blobs` table records which blobs are present
/// and whether they have been uploaded to the sync server yet.
class BlobStore {
  BlobStore(this.database, this.directory, {this.clock = const Clock()});

  final AppDatabase database;
  final Directory directory;
  final Clock clock;

  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  /// Whether [id] looks like a blob id.
  static bool isValidId(String id) => _sha256.hasMatch(id);

  /// The file a blob is (or would be) stored in.
  File fileOf(String sha) {
    if (!isValidId(sha)) throw ArgumentError.value(sha, 'sha', 'not a SHA-256 hex digest');
    return File(p.join(directory.path, sha.substring(0, 2), sha));
  }

  /// Whether the blob is available locally.
  bool has(String sha) =>
      database.db.select('SELECT 1 FROM blobs WHERE sha256 = ?', [sha]).isNotEmpty &&
      fileOf(sha).existsSync();

  /// The blob's bytes, or null if it is not available locally.
  Future<Uint8List?> read(String sha) async => has(sha) ? fileOf(sha).readAsBytes() : null;

  /// Stores [bytes] (a no-op if already present) and returns their id.
  Future<String> putBytes(Uint8List bytes, {required String mime}) async {
    final sha = await Isolate.run(() => sha256.convert(bytes).toString());
    if (!has(sha)) {
      await _writeAtomically(sha, (file) => file.writeAsBytes(bytes, flush: true));
      _record(sha, bytes.length, mime, uploaded: false);
    }
    return sha;
  }

  /// Stores a copy of [source] and returns its id.
  Future<String> putFile(File source, {required String mime}) async {
    final sha = await hashFile(source);
    if (!has(sha)) {
      await _writeAtomically(sha, (file) => source.copy(file.path));
      _record(sha, await source.length(), mime, uploaded: false);
    }
    return sha;
  }

  /// Stores a blob fetched from the sync server after checking its hash.
  /// Throws [FormatException] if the bytes do not match [sha].
  Future<void> putDownloaded(String sha, Uint8List bytes, {String mime = 'application/pdf'}) async {
    final actual = await Isolate.run(() => sha256.convert(bytes).toString());
    if (actual != sha) throw FormatException('Blob $sha arrived corrupted');
    if (!has(sha)) {
      await _writeAtomically(sha, (file) => file.writeAsBytes(bytes, flush: true));
    }
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

  /// The SHA-256 of a file, read in chunks.
  static Future<String> hashFile(File file) async {
    final digest = Completer<Digest>();
    final sink = sha256.startChunkedConversion(
      ChunkedConversionSink<Digest>.withCallback((d) => digest.complete(d.single)),
    );
    await file.openRead().forEach(sink.add);
    sink.close();
    return (await digest.future).toString();
  }

  void _record(String sha, int size, String mime, {required bool uploaded}) {
    database.db.execute(
      '''
      INSERT INTO blobs (sha256, size, mime, created_at, uploaded) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(sha256) DO UPDATE SET uploaded = MAX(uploaded, excluded.uploaded)''',
      [sha, size, mime, clock.nowMs(), uploaded ? 1 : 0],
    );
  }

  /// Writes to a temporary file first, so a crash never leaves a truncated
  /// file under a blob's name.
  Future<void> _writeAtomically(String sha, Future<Object?> Function(File) write) async {
    final target = fileOf(sha);
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.${clock.newId()}.tmp');
    try {
      await write(temp);
      await temp.rename(target.path);
    } catch (_) {
      if (temp.existsSync()) await temp.delete();
      rethrow;
    }
  }
}
