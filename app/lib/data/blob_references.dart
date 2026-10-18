import 'dart:convert';

import 'app_database.dart';
import 'blob_links.dart';
import 'blob_store.dart';
import 'syncable.dart';
import 'tombstone_payloads.dart';

/// Which blobs the local data references: the reference graph behind blob
/// uploads and garbage collection (docs/SYNC_PROTOCOL.md, "Blob garbage
/// collection").
///
/// A blob is referenced by every live (not tombstoned) page background,
/// image template of a page, element, recording (audio parts and waveform), user
/// template and user font, and every blob a live version names: its table blobs, and
/// through them ([BlobLinks]) the packs, backgrounds, images and audio of
/// its rows (format 1: packs, backgrounds and images in the record).
/// Pages, elements and recordings of notebooks in
/// the trash are live rows, so the trash keeps its blobs; "delete forever"
/// tombstones them and releases the blobs.
class BlobReferences {
  BlobReferences(this.database);

  final AppDatabase database;

  late final BlobLinks links = BlobLinks(database.db);

  /// Ids of the blobs this device must keep at [nowMs] (ms): those live
  /// rows and recent tombstones reference ([all] with the tombstones kept
  /// by [TombstonePayloads.retention]). What garbage collection and the
  /// discarding of a cancelled import go by.
  Set<String> kept(int nowMs) => all(tombstonesSince: TombstonePayloads.keptSince(nowMs));

  /// Whether blob [sha] may be among [kept] at [nowMs]: a check of one
  /// blob in SQL, without decoding any JSON (a row merely holding the id
  /// as a string counts, so it errs on keeping). Garbage collection asks
  /// it again right before deleting a blob.
  bool keeps(String sha, int nowMs) {
    const kept = '(deleted = 0 OR updated_at >= ?1)';
    final since = TombstonePayloads.keptSince(nowMs);
    final quoted = '"$sha"';
    return database.db.select(
          'SELECT EXISTS (SELECT 1 FROM pages WHERE $kept AND '
          '(instr(background, ?2) > 0 OR instr(paper_data, ?2) > 0)) '
          'OR EXISTS (SELECT 1 FROM elements WHERE $kept AND instr(data, ?2) > 0) '
          'OR EXISTS (SELECT 1 FROM recordings WHERE $kept AND '
          '(instr(audio, ?2) > 0 OR waveform = ?3)) '
          'OR EXISTS (SELECT 1 FROM templates WHERE deleted = 0 AND blob = ?3) '
          'OR EXISTS (SELECT 1 FROM fonts WHERE deleted = 0 AND blob = ?3) '
          'OR EXISTS (SELECT 1 FROM versions WHERE deleted = 0 AND instr(data, ?2) > 0) '
          'OR EXISTS (SELECT 1 FROM blob_links l WHERE l.child = ?3 AND EXISTS ('
          "  SELECT 1 FROM versions WHERE deleted = 0 AND instr(data, '\"' || l.parent || '\"') > 0"
          ')) AS found',
          [since, quoted, sha],
        ).single['found'] ==
        1;
  }

  /// Ids of all blobs live rows reference, and with [tombstonesSince] (ms)
  /// also those of pages, elements and recordings tombstoned since then:
  /// sync may still bring them back ([TombstonePayloads.retention]).
  Set<String> all({int? tombstonesSince}) {
    final kept = tombstonesSince == null ? 'deleted = 0' : '(deleted = 0 OR updated_at >= ?)';
    final args = [?tombstonesSince];
    // Versions: their table blobs (format 1: packs, page backgrounds and the
    // images in the packs), and what the table blobs name.
    final versions = {
      for (final row in database.db.select('SELECT data FROM versions WHERE deleted = 0'))
        ...inJson(row['data'] as String),
    };
    return {
      ...versions,
      ...links.childrenOf(versions),
      for (final row in database.db.select(
        'SELECT background FROM pages WHERE $kept AND background IS NOT NULL',
        args,
      ))
        ...inJson(row['background'] as String),
      for (final row in database.db.select(
        "SELECT paper_data FROM pages WHERE $kept AND paper_data <> '{}'",
        args,
      ))
        ...inJson(row['paper_data'] as String),
      // Any element type: image elements today, but unknown types from newer
      // app versions are kept with their data, references included.
      for (final row in database.db.select('SELECT data FROM elements WHERE $kept', args))
        ...inJson(row['data'] as String),
      for (final row in database.db.select('SELECT audio FROM recordings WHERE $kept', args))
        ...inJson(row['audio'] as String),
      for (final row in database.db.select(
        "SELECT DISTINCT waveform FROM recordings WHERE $kept AND waveform <> ''",
        args,
      ))
        row['waveform'] as String,
      for (final row in database.db.select('SELECT DISTINCT blob FROM templates WHERE deleted = 0'))
        row['blob'] as String,
      for (final row in database.db.select('SELECT blob FROM fonts WHERE deleted = 0'))
        row['blob'] as String,
    };
  }

  /// Titles of the live notebooks whose live pages, elements or
  /// recordings show blob [sha], sorted (as [keeps], by its id in their
  /// SQL text): to tell the user where a file is missing.
  List<String> notebookTitlesOf(String sha) => [
    for (final row in database.db.select(
      'SELECT title FROM notebooks WHERE deleted = 0 AND id IN ('
      '  SELECT notebook_id FROM pages WHERE deleted = 0 AND '
      '    (instr(background, ?1) > 0 OR instr(paper_data, ?1) > 0) '
      '  UNION SELECT coalesce(p.notebook_id, e.surface_id) FROM elements e '
      '    LEFT JOIN pages p ON p.id = e.surface_id '
      '    WHERE e.deleted = 0 AND instr(e.data, ?1) > 0 '
      '  UNION SELECT notebook_id FROM recordings WHERE deleted = 0 AND '
      '    (instr(audio, ?1) > 0 OR waveform = ?2)'
      ') ORDER BY title',
      ['"$sha"', sha],
    ))
      row['title'] as String,
  ];

  /// The blobs record [record] needs on the server before it: those its
  /// data names and, for a version, those its table blobs name.
  Set<String> ofRecord(SyncRecord record) {
    final named = inValue(record.data);
    if (record.collection != 'versions' || named.isEmpty) return named;
    return {...named, ...links.childrenOf(named)};
  }

  /// The blob ids among the strings of a JSON document (malformed: none).
  static Set<String> inJson(String json) {
    // Most documents (paper looks, text boxes) hold none: skip decoding
    // those (it took most of a garbage collection's scan).
    if (!_mayHoldId(json)) return const {};
    try {
      return inValue(jsonDecode(json));
    } on FormatException {
      return const {};
    }
  }

  /// Whether [json] has a string of 64 lowercase hex digits, as encoded
  /// (hex needs no escapes). A plain scan: a RegExp is slower than decoding.
  static bool _mayHoldId(String json) {
    var run = -1; // Hex digits since an opening quote; -1: none open.
    for (var i = 0; i < json.length; i++) {
      final c = json.codeUnitAt(i);
      if (c == 0x22) {
        if (run == 64) return true;
        run = 0;
      } else if (run >= 0 && ((c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66))) {
        run++;
      } else {
        run = -1;
      }
    }
    return false;
  }

  /// The blob ids among the strings of a decoded JSON value (e.g. a sync
  /// record's `data`): every string that is a well-formed blob id.
  static Set<String> inValue(Object? value) {
    final found = <String>{};
    void visit(Object? v) {
      switch (v) {
        case String() when v.length == 64 && BlobStore.isValidId(v):
          found.add(v);
        case Map():
          v.values.forEach(visit);
        case List():
          v.forEach(visit);
      }
    }

    visit(value);
    return found;
  }
}
