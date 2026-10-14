import 'dart:async';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../domain/cancellation.dart';
import '../blob_references.dart';
import '../blob_store.dart';
import 'len_format.dart';
import 'len_import_commit.dart';
import 'len_remap.dart';
import 'len_source.dart';
import 'len_stores.dart';

/// What an import brought in.
class LenImportResult {
  LenImportResult({
    required this.manifest,
    required this.notebooks,
    required this.folders,
    required this.folder,
    required this.skipped,
    required this.missingBlobs,
    this.lostParts = 0,
    this.problems = const [],
  });

  final LenManifest manifest;

  /// The new notebooks' ids.
  final List<String> notebooks;

  /// The folders made (the backup's own folder too).
  final List<String> folders;

  /// The folder holding what was imported (the backup's folder, or the
  /// copy of an exported folder); null when it went to the given parent.
  final String? folder;

  /// Records that could not be read (malformed or damaged), left out.
  final int skipped;

  /// Files (PDFs, images, audio) the Len file lacked or held damaged:
  /// shown as missing.
  final int missingBlobs;

  /// Parts of the records that were damaged as a whole (left out).
  final int lostParts;

  /// What was damaged, in technical words (for Details).
  final List<String> problems;

  /// Whether nothing was left out.
  bool get complete => skipped == 0 && missingBlobs == 0 && lostParts == 0;
}

/// Imports a Len file ([LenFormat]) as a copy: every folder, notebook and
/// page gets a new id, so nothing here is replaced and importing twice
/// gives two copies. A restored backup ([keepIds]) keeps the ids of what
/// isn't here, so restoring it again can tell (UX_AUDIT R8-16).
///
/// Blobs go first (each checked against its hash), then the records part
/// by part, in time-budgeted slices of one transaction each, with the
/// event loop free in between. Pages and content stay invisible (their
/// notebooks are written last) and unsynced (written clean) until
/// everything is in; then one transaction adds the folders, templates and
/// notebooks and marks it all for sync. Whatever is damaged (a blob, a
/// line, a whole part) is left out and reported, and the rest imported
/// (R8-14); an error that isn't about the file, or Cancel, removes
/// whatever was written.
class LenArchiveReader {
  LenArchiveReader(this.stores, this.blobs, {required this.deviceId, this.clock = const Clock()});

  final LenStores stores;
  final BlobStore blobs;
  final String deviceId;
  final Clock clock;

  /// UI-thread time spent reading and writing records before the event
  /// loop gets a turn.
  static const sliceBudget = Duration(milliseconds: 8);

  /// The notebooks of [source] that are here already (id → title; in the
  /// Trash too): restoring a backup again, or on the device it came from.
  Map<String, String> present(LenSource source) {
    return {
      for (final MapEntry(:key, :value) in source.contents.notebooks.entries)
        if (_here('notebooks', key)) key: value,
    };
  }

  /// A version for the records of a restore keeping the ids [keep]: [now],
  /// or later than the deletion here of any of them (a tombstone stamped
  /// by a device whose clock is ahead), so the restore wins wherever it
  /// syncs to.
  int _versionAbove(Set<String> keep, int now) {
    const onSurfaces =
        '(surface_id = ?1 OR surface_id IN (SELECT id FROM pages WHERE notebook_id = ?1))';
    const rows = [
      ('folders', 'id = ?1'),
      ('notebooks', 'id = ?1'),
      ('pages', 'notebook_id = ?1'),
      ('outline', 'notebook_id = ?1'),
      ('recordings', 'notebook_id = ?1'),
      ('strokes', onSurfaces),
      ('elements', onSurfaces),
    ];
    var version = now;
    for (final id in keep) {
      for (final (table, where) in rows) {
        final latest = stores.any.db.select(
          'SELECT MAX(updated_at) AS v FROM $table WHERE $where',
          [id],
        ).first['v'];
        if (latest is int && latest >= version) version = latest + 1;
      }
    }
    return version;
  }

  /// Whether a live row [id] of [table] is here.
  bool _here(String table, String id) =>
      stores.any.db.select('SELECT 1 FROM $table WHERE id = ? AND deleted = 0', [id]).isNotEmpty;

  /// Imports [source] into folder [parent] (null: the library's top level)
  /// and closes it. With [folderName], everything goes into a new folder of
  /// that name (and [folderColor]) inside [parent] instead (a restored
  /// backup). With [keepIds], folders and notebooks that aren't here keep
  /// their ids; notebooks in [skip] are left out.
  Future<LenImportResult> import(
    LenSource source, {
    String? parent,
    String? folderName,
    int folderColor = 0,
    bool keepIds = false,
    Set<String> skip = const {},
    CancellationToken? cancel,
    void Function(double done)? onProgress,
  }) async {
    try {
      final contents = keepIds ? source.contents : null;
      final keep = {
        if (contents != null) ...[
          for (final id in contents.folders)
            if (!_here('folders', id)) id,
          for (final id in contents.notebooks.keys)
            if (!_here('notebooks', id)) id,
        ],
      };
      final remap = LenRemap(
        deviceId: deviceId,
        version: _versionAbove(keep, clock.nowMs()),
        clock: clock,
        keep: keep,
        skip: skip,
      );
      return await _import(
        source,
        remap,
        parent: parent,
        folderName: folderName,
        folderColor: folderColor,
        cancel: cancel,
        onProgress: onProgress,
      );
    } finally {
      await source.close();
    }
  }

  Future<LenImportResult> _import(
    LenSource source,
    LenRemap remap, {
    String? parent,
    String? folderName,
    required int folderColor,
    CancellationToken? cancel,
    void Function(double done)? onProgress,
  }) async {
    final archive = source.archive;
    final parts = source.parts;
    final problems = <String>[];
    if (archive.find(LenFormat.blobIndexName) case final entry?) await LenSource.load(entry);
    final index = _blobIndex(archive, problems);
    final steps = math.max(1, index.length + parts.length);
    var done = 0;
    final commit = LenImportCommit(stores, remap);
    final stored = <String>[];
    var missing = 0;
    try {
      for (final MapEntry(key: sha, value: mime) in index.entries) {
        cancel?.check();
        final entry = archive.find(LenFormat.blobName(sha));
        if (entry == null || !entry.isFile) {
          missing++;
        } else {
          switch (await _putBlob(entry, sha, mime)) {
            case null:
              missing++;
              problems.add('Damaged file $sha');
            case true:
              stored.add(sha);
            case false:
          }
        }
        onProgress?.call(++done / steps);
      }
      var skipped = 0, lost = 0;
      for (final part in parts) {
        cancel?.check();
        final List<String> lines;
        try {
          lines = await LenSource.recordLines(part);
        } on LenArchiveException catch (e) {
          problems.add('${e.details}');
          lost++;
          continue;
        }
        final before = skipped;
        // Parsed and written in slices of [sliceBudget], each in its own
        // transaction, with the event loop free in between: a part is
        // thousands of records (seconds of the UI thread in a browser).
        for (var i = 0; i < lines.length;) {
          final slice = Stopwatch()..start();
          stores.any.database.transaction(() {
            do {
              if (!commit.add(LenSource.parseRecord(lines[i++]))) skipped++;
            } while (i < lines.length && slice.elapsed < sliceBudget);
          });
          await Future<void>.delayed(Duration.zero);
          cancel?.check();
        }
        if (skipped > before) problems.add('${part.name}: ${skipped - before} unreadable');
        onProgress?.call(++done / steps);
      }
      cancel?.check();
      final result = commit.finish(
        parent: parent,
        folderName: folderName,
        folderColor: folderColor,
        onlyUsedFolders: remap.skip.isNotEmpty,
      );
      return LenImportResult(
        manifest: source.manifest,
        notebooks: result.notebooks,
        folders: result.folders,
        folder: result.folder,
        skipped: skipped + result.skipped,
        missingBlobs: missing,
        lostParts: lost,
        problems: problems,
      );
    } catch (_) {
      commit.discard();
      final references = BlobReferences(stores.any.database);
      Set<String> referenced() => references.kept(clock.nowMs());
      for (final sha in stored) {
        await blobs.discardIfUnreferenced(sha, referenced);
      }
      rethrow;
    }
  }

  /// The blobs the file says it holds, with their MIME types. If its index
  /// is damaged, the blobs it holds, of unknown types.
  static Map<String, String> _blobIndex(Archive archive, List<String> problems) {
    final entry = archive.find(LenFormat.blobIndexName);
    if (entry == null) return const {};
    Object? json;
    try {
      json = LenSource.readJson(entry);
    } on LenArchiveException catch (e) {
      problems.add('${e.details}');
    }
    if (json is! Map<String, Object?>) {
      return {
        for (final f in archive.files)
          if (f.isFile && f.name.startsWith(LenFormat.blobsPrefix))
            if (f.name.substring(LenFormat.blobsPrefix.length) case final sha
                when BlobStore.isValidId(sha))
              sha: 'application/octet-stream',
      };
    }
    return {
      for (final MapEntry(:key, :value) in json.entries)
        if (BlobStore.isValidId(key))
          key: switch (value) {
            {'mime': final String mime} => mime,
            _ => 'application/octet-stream',
          },
    };
  }

  /// Stores blob [sha] from [entry] in chunks; whether it was new here, or
  /// null if it is damaged (left out).
  Future<bool?> _putBlob(ArchiveFile entry, String sha, String mime) async {
    try {
      return await blobs.putVerified(sha, () => LenSource.chunks(entry), mime: mime);
    } on FormatException catch (e) {
      debugPrint('Damaged blob: ${e.message}');
      return null;
    } on RangeError catch (e) {
      debugPrint('Damaged blob: $e');
      return null;
    } finally {
      entry.closeSync();
    }
  }
}
