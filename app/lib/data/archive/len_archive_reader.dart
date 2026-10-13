import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../domain/cancellation.dart';
import '../blob_references.dart';
import '../blob_store.dart';
import '../syncable.dart';
import 'len_format.dart';
import 'len_import_commit.dart';
import 'len_remap.dart';
import 'len_stores.dart';

/// What an import brought in.
class LenImportResult {
  LenImportResult({
    required this.manifest,
    required this.notebooks,
    required this.folder,
    required this.skipped,
    required this.missingBlobs,
  });

  final LenManifest manifest;

  /// The new notebooks' ids (the trash's too, for a backup).
  final List<String> notebooks;

  /// The folder holding what was imported (the backup's folder, or the
  /// copy of an exported folder); null when it went to the given parent.
  final String? folder;

  /// Records that could not be read (malformed), left out.
  final int skipped;

  /// Files (PDFs, images, audio) the Len file lacked: shown as missing.
  final int missingBlobs;
}

/// Imports a Len file ([LenFormat]) as a copy: every folder, notebook and
/// page gets a new id, so nothing here is replaced and importing twice
/// gives two copies.
///
/// Blobs go first (each checked against its hash), then the records part
/// by part, each part in one transaction, with the event loop free in
/// between. Pages and content stay invisible (their notebooks are written
/// last) and unsynced (written clean) until everything is in; then one
/// transaction adds the folders, templates and notebooks and marks it all
/// for sync. A damaged file, an error or Cancel removes whatever was
/// written, so an import is all or nothing.
class LenArchiveReader {
  LenArchiveReader(this.stores, this.blobs, {required this.deviceId, this.clock = const Clock()});

  final LenStores stores;
  final BlobStore blobs;
  final String deviceId;
  final Clock clock;

  /// Opens [input] and reads its manifest; throws [LenArchiveException] if
  /// it is not a Len file this build reads.
  static (Archive, LenManifest) open(InputStream input) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } on Object catch (e) {
      throw LenArchiveException.notLen('$e');
    }
    final entry = archive.find(LenFormat.manifestName);
    if (entry == null) throw const LenArchiveException.notLen('no manifest');
    return (archive, LenManifest.fromJson(_json(entry)));
  }

  /// Imports [input] into folder [parent] (null: the library's top level).
  /// With [folderName], everything goes into a new folder of that name
  /// (and [folderColor]) inside [parent] instead (a restored backup).
  Future<LenImportResult> import(
    InputStream input, {
    String? parent,
    String? folderName,
    int folderColor = 0,
    CancellationToken? cancel,
    void Function(double done)? onProgress,
  }) async {
    try {
      return await _import(
        input,
        parent: parent,
        folderName: folderName,
        folderColor: folderColor,
        cancel: cancel,
        onProgress: onProgress,
      );
    } finally {
      await input.close();
    }
  }

  Future<LenImportResult> _import(
    InputStream input, {
    String? parent,
    String? folderName,
    required int folderColor,
    CancellationToken? cancel,
    void Function(double done)? onProgress,
  }) async {
    final (archive, manifest) = open(input);
    final parts = [
      for (final f in archive.files)
        if (f.isFile && f.name.startsWith(LenFormat.recordsPrefix)) f,
    ]..sort((a, b) => a.name.compareTo(b.name));
    final index = _blobIndex(archive);
    final steps = math.max(1, index.length + parts.length);
    var done = 0;
    final remap = LenRemap(deviceId: deviceId, version: clock.nowMs(), clock: clock);
    final commit = LenImportCommit(stores, remap);
    final stored = <String>[];
    var missing = 0;
    try {
      for (final MapEntry(key: sha, value: mime) in index.entries) {
        cancel?.check();
        final entry = archive.find(LenFormat.blobName(sha));
        if (entry == null || !entry.isFile) {
          missing++;
        } else if (await _putBlob(entry, sha, mime)) {
          stored.add(sha);
        }
        onProgress?.call(++done / steps);
      }
      var skipped = 0;
      for (final part in parts) {
        cancel?.check();
        final records = _records(part);
        stores.any.database.transaction(() {
          for (final record in records) {
            if (!commit.add(record)) skipped++;
          }
        });
        part.closeSync();
        onProgress?.call(++done / steps);
        await Future<void>.delayed(Duration.zero);
      }
      cancel?.check();
      final result = commit.finish(
        parent: parent,
        folderName: folderName,
        folderColor: folderColor,
      );
      return LenImportResult(
        manifest: manifest,
        notebooks: result.notebooks,
        folder: result.folder,
        skipped: skipped + result.skipped,
        missingBlobs: missing,
      );
    } catch (_) {
      commit.discard();
      final referenced = BlobReferences(stores.any.database).all;
      for (final sha in stored) {
        await blobs.discardIfUnreferenced(sha, referenced);
      }
      rethrow;
    }
  }

  /// The blobs the file says it holds, with their MIME types.
  static Map<String, String> _blobIndex(Archive archive) {
    final entry = archive.find(LenFormat.blobIndexName);
    if (entry == null) return const {};
    final json = _json(entry);
    if (json is! Map<String, Object?>) throw const LenArchiveException.damaged('blob index');
    return {
      for (final MapEntry(:key, :value) in json.entries)
        if (BlobStore.isValidId(key))
          key: switch (value) {
            {'mime': final String mime} => mime,
            _ => 'application/octet-stream',
          },
    };
  }

  /// Stores blob [sha] from [entry] in chunks; whether it was new here.
  Future<bool> _putBlob(ArchiveFile entry, String sha, String mime) async {
    try {
      return await blobs.putVerified(sha, () => _chunks(entry), mime: mime);
    } on FormatException catch (e) {
      throw LenArchiveException.damaged(e.message);
    } on RangeError catch (e) {
      throw LenArchiveException.damaged('$e');
    } finally {
      entry.closeSync();
    }
  }

  static Stream<List<int>> _chunks(ArchiveFile entry) async* {
    final InputStream? content;
    try {
      content = entry.getContent();
    } on Object catch (e) {
      throw FormatException('Unreadable entry ${entry.name}: $e');
    }
    if (content == null) return;
    content.reset();
    while (!content.isEOS) {
      yield content.readBytes(math.min(1 << 16, content.length)).toUint8List();
    }
  }

  /// The records of [part]; throws [LenArchiveException] if it is damaged.
  /// Records that are not records (wrong shape) are skipped by [SyncRecord]'s
  /// parser later, so a single odd record never fails an import.
  static List<SyncRecord?> _records(ArchiveFile part) {
    final String text;
    try {
      text = utf8.decode(part.readBytes() ?? const []);
    } on Object catch (e) {
      throw LenArchiveException.damaged('${part.name}: $e');
    }
    final records = <SyncRecord?>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.isEmpty) continue;
      final Object? json;
      try {
        json = jsonDecode(line);
      } on FormatException catch (e) {
        throw LenArchiveException.damaged('${part.name}: ${e.message}');
      }
      try {
        records.add(SyncRecord.fromJson(json));
      } on FormatException catch (e) {
        debugPrint('Skipping a malformed record: ${e.message}');
        records.add(null);
      }
    }
    return records;
  }

  static Object? _json(ArchiveFile entry) {
    try {
      return jsonDecode(utf8.decode(entry.readBytes() ?? const []));
    } on Object catch (e) {
      throw LenArchiveException.damaged('${entry.name}: $e');
    } finally {
      entry.closeSync();
    }
  }
}
