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
  LenArchiveWriter(this.stores, this.blobs, {this.openBlobFile, this.clock = const Clock()});

  final LenStores stores;
  final BlobStore blobs;
  final BlobFileOpener? openBlobFile;
  final Clock clock;

  /// Rows read from the database at a time.
  static const _pageSize = 500;

  /// Writes [scope] into [output] (left open). [onProgress] gets the
  /// fraction done; a [cancel]led token stops with [Cancelled] between
  /// steps (the caller discards the output).
  Future<LenWriteReport> write(
    LenScope scope,
    OutputStream output, {
    CancellationToken? cancel,
    void Function(double done)? onProgress,
  }) async {
    final resolved = ResolvedScope.of(scope, stores);
    final zip = ZipEncoder()..startEncode(output);
    final manifest = LenManifest(kind: scope.kind, title: resolved.title, createdAt: clock.nowMs());
    zip.add(ArchiveFile.string(LenFormat.manifestName, jsonEncode(manifest.toJson())));

    final referenced = <String>{};
    final parts = _PartWriter(zip);
    var records = 0;
    final total = resolved.estimate + 1;
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
          referenced.addAll(BlobReferences.inValue(record.data));
          parts.add(record);
          records++;
        }
        onProgress?.call(0.5 * records / total);
        // Lets the UI breathe between pages (progress, Cancel).
        await Future<void>.delayed(Duration.zero);
        if (rows.length < _pageSize) break;
      }
    }
    parts.close();

    final included = <String, Map<String, Object?>>{};
    var missing = 0;
    final sorted = referenced.toList()..sort();
    for (final sha in sorted) {
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
      await _addBlob(zip, sha);
      done++;
      onProgress?.call(0.5 + 0.5 * done / included.length);
    }
    zip.endEncode();
    onProgress?.call(1);
    return LenWriteReport(records: records, blobs: included.length, missingBlobs: missing);
  }

  Future<void> _addBlob(ZipEncoder zip, String sha) async {
    final path = blobs.localPath(sha);
    var input = path == null ? null : openBlobFile?.call(path);
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
