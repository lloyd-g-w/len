import '../../domain/notebook_version.dart';
import '../repositories.dart';
import '../syncable_table.dart';
import 'canonical_json.dart';

/// Restores and copies the records a version keeps whole (docs/ARCHITECTURE.md,
/// "Version history"): recordings, outline entries and recognised
/// handwriting, written as local edits (synced like any). A record that is
/// malformed for its collection is left out.
abstract final class VersionRecords {
  /// Makes the handwriting recognised on [surfaceId] [text] (null: none,
  /// tombstoning what there is).
  static void restoreText(Repositories r, String surfaceId, Map<String, Object?>? text) {
    final store = r.recognisedText;
    final rows = store.db.select('SELECT * FROM recognised_text WHERE id = ? AND deleted = 0', [
      surfaceId,
    ]);
    final live = rows.isEmpty ? null : store.rowToRecord(rows.first).data;
    if (text == null) {
      if (live != null) store.tombstoneLocal(surfaceId);
    } else if (!_same(live, text)) {
      _write(store, surfaceId, text);
    }
  }

  /// Makes [store]'s live records of [notebookId] [records]: by id,
  /// rewritten where they differ, the others tombstoned (unless not
  /// [removeOthers]).
  static void restore(
    SyncableTable store,
    String notebookId,
    List<VersionRecord> records, {
    bool removeOthers = true,
  }) {
    final live = {
      for (final row in store.db.select(
        'SELECT * FROM ${store.table} WHERE notebook_id = ? AND deleted = 0',
        [notebookId],
      ))
        row['id'] as String: store.rowToRecord(row).data,
    };
    for (final (:id, :data) in records) {
      final wanted = {...data, 'notebookId': notebookId};
      if (!_same(live[id], wanted)) _write(store, id, wanted);
    }
    if (!removeOthers) return;
    final kept = {for (final r in records) r.id};
    for (final id in live.keys) {
      if (!kept.contains(id)) store.tombstoneLocal(id);
    }
  }

  /// Writes [body]'s recordings and outline entries as those of notebook
  /// [copyId] under new ids ([newId]); entries follow their pages
  /// ([renamed]: old id → new id), those of pages not copied are left out,
  /// and parents not copied make entries top-level ones. Recognised
  /// handwriting is not copied (its lines are keyed by stroke ids; the
  /// copy is read again, as a duplicated notebook is).
  static void copy(
    Repositories r,
    VersionBody body,
    String copyId,
    Map<String, String> renamed,
    String Function() newId,
  ) {
    for (final (id: _, :data) in body.recordings ?? const <VersionRecord>[]) {
      _write(r.recordings, newId(), {...data, 'notebookId': copyId});
    }
    final outline = body.outline ?? const <VersionRecord>[];
    final ids = {for (final e in outline) e.id: newId()};
    for (final (:id, :data) in outline) {
      final page = renamed[data['pageId']];
      if (page == null) continue;
      _write(r.outline, ids[id]!, {
        ...data,
        'notebookId': copyId,
        'pageId': page,
        'parentId': ids[data['parentId']],
      });
    }
  }

  static bool _same(Map<String, Object?>? a, Map<String, Object?> b) =>
      a != null && CanonicalJson.encode(a) == CanonicalJson.encode(b);

  /// [SyncableTable.writeLocal], leaving out a malformed record.
  static void _write(SyncableTable store, String id, Map<String, Object?> data) {
    try {
      store.writeLocal(id, data);
    } on FormatException {
      // Left out (docs/SYNC_PROTOCOL.md, "Version history").
    }
  }
}
