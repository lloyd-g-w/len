import 'dart:convert';

import 'app_database.dart';
import 'blob_store.dart';
import 'tombstone_payloads.dart';

/// Which blobs the local data references: the reference graph behind blob
/// uploads and garbage collection (docs/SYNC_PROTOCOL.md, "Blob garbage
/// collection").
///
/// A blob is referenced by every live (not tombstoned) page background,
/// image template of a page, element, recording (audio parts and waveform) and user
/// template. Pages, elements and recordings of notebooks in
/// the trash are live rows, so the trash keeps its blobs; "delete forever"
/// tombstones them and releases the blobs.
class BlobReferences {
  BlobReferences(this.database);

  final AppDatabase database;

  /// Ids of all blobs live rows reference, and with [tombstonesSince] (ms)
  /// also those of pages, elements and recordings tombstoned since then:
  /// sync may still bring them back ([TombstonePayloads.retention]).
  Set<String> all({int? tombstonesSince}) {
    final kept = tombstonesSince == null ? 'deleted = 0' : '(deleted = 0 OR updated_at >= ?)';
    final args = [?tombstonesSince];
    return {
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
    };
  }

  /// The blob ids among the strings of a JSON document (malformed: none).
  static Set<String> inJson(String json) {
    try {
      return inValue(jsonDecode(json));
    } on FormatException {
      return const {};
    }
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
