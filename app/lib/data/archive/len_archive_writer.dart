import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/clock.dart';
import '../../domain/cancellation.dart';
import '../blob_references.dart';
import '../blob_store.dart';
import '../syncable.dart';
import 'len_format.dart';
import 'len_scope.dart';
import 'len_stores.dart';

/// Opens blob file [path] for reading in chunks, or null where blobs are
/// not files (browsers): they are then read into memory one at a time.
typedef BlobFileOpener = InputStream? Function(String path);

/// The zip checksum (CRC-32) of blob file [path], worked out off the UI
/// thread; null where that isn't possible (then it is worked out as the
/// blob is written).
typedef BlobFileChecksum = Future<int?> Function(String path);

/// Downloads blob [sha] if it isn't here yet; whether it is now.
typedef BlobFetcher = Future<bool> Function(String sha);

/// What a written Len file left out.
class LenWriteReport {
  LenWriteReport({required this.records, required this.blobs, required this.missingBlobs});

  /// Records written.
  final int records;

  /// Blobs written.
  final int blobs;

  /// Blobs referenced but not on this device (not downloaded yet): their
  /// pages show them as missing after an import.
  final int missingBlobs;
}

/// Writes a [LenScope] as a Len file ([LenFormat]) into a zip stream.
///
/// Streams: records are read from the database a page at a time and
/// written in parts of about [LenFormat.partBytes]; blobs one at a time,
/// straight from their files where the platform has files. So neither a
/// notebook with a million strokes nor a library of textbooks is ever
/// held in memory at once.
class LenArchiveWriter {
  LenArchiveWriter(
    this.stores,
    this.blobs, {
    this.openBlobFile,
    this.checksumBlobFile,
    this.fetchBlob,
    this.clock = const Clock(),
  });

  final LenStores stores;
  final BlobStore blobs;
  final BlobFileOpener? openBlobFile;

  /// Checksums blob files off the UI thread (natively, UX_AUDIT R8-19), so
  /// adding one only copies it.
  final BlobFileChecksum? checksumBlobFile;

  /// Downloads blobs not here yet (from the sync server), so a backup
  /// holds them too (UX_AUDIT R8-22).
  final BlobFetcher? fetchBlob;
  final Clock clock;

  /// Whether [record] belongs in the file with the [notebooks] and
  /// [surfaces] written before it (noting its own).
  static bool _inFile(SyncRecord record, Set<String> notebooks, Set<String> surfaces) {
    final data = record.data;
    switch (record.collection) {
      case 'notebooks':
        notebooks.add(record.id);
        surfaces.add(record.id);
      case 'pages' || 'outline' || 'recordings':
        if (!notebooks.contains(data?['notebookId'])) return false;
        if (record.collection == 'pages') surfaces.add(record.id);
      case 'strokes' || 'elements':
        return surfaces.contains(data?['surfaceId']);
    }
    return true;
  }

  /// Rows read from the database at a time.
  static const _pageSize = 500;

  /// Writes [scope] into [output] (left open). [onProgress] gets the
  /// fraction done; a [cancel]led token stops with [Cancelled] between
  /// steps (the caller discards the output). [drain], if given, is awaited
  /// between steps (an output that writes asynchronously catches up).
  Future<LenWriteReport> write(
    LenScope scope,
    OutputStream output, {
    CancellationToken? cancel,
    void Function(double done)? onProgress,
    Future<void> Function()? drain,
  }) async {
    final resolved = ResolvedScope.of(scope, stores);
    final zip = ZipEncoder()..startEncode(output);
    final manifest = LenManifest(kind: scope.kind, title: resolved.title, createdAt: clock.nowMs());
    zip.add(ArchiveFile.string(LenFormat.manifestName, jsonEncode(manifest.toJson())));

    final referenced = <String>{};
    final parts = _PartWriter(zip);
    var records = 0;
    final total = resolved.estimate + 1;
    // The notebooks and surfaces (notebooks, pages) written: the database
    // changes while the file is written (sync, edits), and what came after
    // its notebook or page was read would be on none in the file.
    final notebooks = <String>{}, surfaces = <String>{};
    for (final (collection, where, args) in resolved.queries()) {
      final store = stores.of(collection);
      String? after;
      while (true) {
        cancel?.check();
        final rows = store.db.select(
          'SELECT * FROM ${store.table} WHERE deleted = 0 AND ($where) AND id > ? '
          'ORDER BY id LIMIT $_pageSize',
          [...args, after ?? ''],
        );
        if (rows.isEmpty) break;
        after = rows.last['id'] as String;
        for (final row in rows) {
          final record = resolved.adjust(store.rowToRecord(row));
          if (!_inFile(record, notebooks, surfaces)) continue;
          referenced.addAll(BlobReferences.inValue(record.data));
          parts.add(record);
          records++;
        }
        onProgress?.call(0.5 * records / total);
        // Lets the UI breathe between pages (progress, Cancel).
        await (drain?.call() ?? Future<void>.delayed(Duration.zero));
        if (rows.length < _pageSize) break;
      }
    }
    parts.close();

    final included = <String, Map<String, Object?>>{};
    var missing = 0;
    final sorted = referenced.toList()..sort();
    // One failed download (offline) stops the others.
    var fetching = fetchBlob != null;
    for (final sha in sorted) {
      if (fetching && !await blobs.has(sha)) {
        cancel?.check();
        fetching = await fetchBlob!(sha);
      }
      final size = blobs.sizeOf(sha);
      if (size == null || !await blobs.has(sha)) {
        missing++;
        continue;
      }
      included[sha] = {'mime': blobs.mimeOf(sha), 'size': size};
    }
    zip.add(ArchiveFile.string(LenFormat.blobIndexName, jsonEncode(included)));
    var done = 0;
    for (final sha in included.keys) {
      cancel?.check();
      await _addBlob(zip, sha, cancel);
      await drain?.call();
      done++;
      onProgress?.call(0.5 + 0.5 * done / included.length);
    }
    zip.endEncode();
    onProgress?.call(1);
    return LenWriteReport(records: records, blobs: included.length, missingBlobs: missing);
  }

  Future<void> _addBlob(ZipEncoder zip, String sha, CancellationToken? cancel) async {
    // Its copy here may have gone since the index was written (Settings →
    // Storage → Free up meanwhile): downloaded again.
    // Awaited apart: dart2wasm miscompiles `!await a && await b` (see
    // test/wasm_await_rules_test.dart).
    final here = await blobs.has(sha);
    if (!here && !(await fetchBlob?.call(sha) ?? false)) {
      throw StateError('Blob $sha vanished while exporting');
    }
    cancel?.check();
    final path = blobs.localPath(sha);
    final checksum = checksumBlobFile;
    final crc = path == null || checksum == null ? null : await checksum(path);
    cancel?.check();
    var input = path == null ? null : openBlobFile?.call(path);
    if (input != null && crc != null) {
      try {
        // Stored with its checksum known: the encoder only copies it.
        zip.add(
          ArchiveFile.file(LenFormat.blobName(sha), input.length, _Checksummed(input))
            ..compression = CompressionType.none
            ..crc32 = crc,
          autoClose: false,
        );
      } finally {
        await input.close();
      }
      return;
    }
    if (input == null) {
      final bytes = await blobs.read(sha);
      if (bytes == null) throw StateError('Blob $sha vanished while exporting');
      input = InputMemoryStream(bytes);
    }
    try {
      zip.add(
        ArchiveFile.stream(LenFormat.blobName(sha), input)..compression = CompressionType.none,
        autoClose: false,
      );
    } finally {
      await input.close();
    }
  }
}

/// Collects records into parts of about [LenFormat.partBytes] and writes
/// each as one compressed entry.
class _PartWriter {
  _PartWriter(this._zip);

  final ZipEncoder _zip;
  final BytesBuilder _part = BytesBuilder(copy: false);
  int _parts = 0;

  void add(SyncRecord record) {
    _part
      ..add(utf8.encode(jsonEncode(record.toJson())))
      ..addByte(0x0A);
    if (_part.length >= LenFormat.partBytes) _flush();
  }

  void close() {
    if (_part.isNotEmpty || _parts == 0) _flush();
  }

  void _flush() {
    _parts++;
    _zip.add(ArchiveFile.bytes(LenFormat.recordsName(_parts), _part.takeBytes()));
  }
}

/// A blob file's content whose checksum is already known: to the encoder
/// it is "compressed" (stored), so it writes it as it is without reading
/// it twice or checksumming it.
class _Checksummed extends FileContent {
  _Checksummed(this._input);

  final InputStream _input;

  @override
  bool get isCompressed => true;

  @override
  int get length => _input.length;

  @override
  InputStream getStream({bool decompress = true}) => _input;

  @override
  void write(OutputStream output) => output.writeStream(_input);

  @override
  Future<void> close() => _input.close();

  @override
  void closeSync() => _input.closeSync();
}
