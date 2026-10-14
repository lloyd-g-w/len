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

  /// Ids of the blobs this device must keep at [nowMs] (ms): those live
  /// rows and recent tombstones reference ([all] with the tombstones kept
  /// by [TombstonePayloads.retention]). What garbage collection and the
  /// discarding of a cancelled import go by.
  Set<String> kept(int nowMs) => all(tombstonesSince: TombstonePayloads.keptSince(nowMs));

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
