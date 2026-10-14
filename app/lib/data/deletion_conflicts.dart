import 'package:sqlite3/common.dart';

import 'notebook_repository.dart';
import 'syncable_table.dart';

/// Identifies one deletion: all tombstones it wrote share the device and
/// the version (see [NotebookRepository.delete] and
/// [NotebookRepository.deletePage]).
typedef DeletionMark = ({String deviceId, int version});

/// What [DeletionConflicts] brought back.
class Revival {
  /// Notebooks that got pages, recordings or outline entries back, or were
  /// themselves revived (into the trash).
  final Set<String> notebooks = {};

  /// Surfaces (pages, canvases) that got content back.
  final Set<String> surfaces = {};

  bool get isEmpty => notebooks.isEmpty && surfaces.isEmpty;
}

/// Undoes deletions that raced edits on another device, so no edit is
/// silently lost (docs/SYNC_PROTOCOL.md, "Deletion conflicts").
///
/// A notebook deleted forever on one device while another kept working in
/// it comes back into the trash with everything the deletion removed; a
/// deleted page another device wrote on comes back into its notebook with
/// its content. Every device that holds the deleted content does this when
/// it sees the conflict, so it does not matter which one syncs first:
///
/// - after a pull, a known (not placeholder) tombstoned page holding live
///   strokes or elements, or a known tombstoned notebook holding live pages,
///   recordings, outline entries or canvas content ([resolve]);
/// - while pulling, a known tombstoned notebook or page replaced by a live
///   record ([tombstoneOf] before applying it, then [reviveDeleted]).
///
/// Revived rows become local edits, so they sync like any other.
class DeletionConflicts {
  DeletionConflicts(this.notebooks);

  final NotebookRepository notebooks;

  CommonDatabase get _db => notebooks.db;

  /// The mark of notebook or page [id] if it is a known tombstone of
  /// [collection] (`notebooks` or `pages`), else null.
  DeletionMark? tombstoneOf(String collection, String id) {
    final known = switch (collection) {
      'notebooks' => 'created_at <> 0',
      'pages' => "notebook_id <> ''",
      _ => null,
    };
    if (known == null) return null;
    final rows = notebooks.database.select(
      'SELECT device_id, updated_at FROM $collection WHERE id = ? AND deleted = 1 AND $known',
      [id],
    );
    return rows.isEmpty ? null : _markOf(rows.first);
  }

  /// Brings back what the deletion [mark] of notebook or page [id] removed,
  /// now that a live version of it arrived (it was edited elsewhere while
  /// being deleted here). A notebook goes to the trash.
  void reviveDeleted(String collection, String id, DeletionMark mark, Revival out) {
    if (collection == 'notebooks') _reviveNotebook(id, mark, out);
    if (collection == 'pages') _revivePage(id, mark, out);
  }

  /// Revives deleted pages and notebooks that hold live content.
  void resolve(Revival out) {
    final pages = _db.select('''
      SELECT id, device_id, updated_at FROM pages p
      WHERE deleted = 1 AND notebook_id <> '' AND (
        EXISTS (SELECT 1 FROM strokes WHERE surface_id = p.id AND deleted = 0) OR
        EXISTS (SELECT 1 FROM elements WHERE surface_id = p.id AND deleted = 0))''');
    for (final row in pages) {
      _revivePage(row['id'] as String, _markOf(row), out);
    }
    // After the pages: a revived page is live content of its notebook.
    final notebooks = _db.select('''
      SELECT id, device_id, updated_at FROM notebooks n
      WHERE deleted = 1 AND created_at <> 0 AND (
        EXISTS (SELECT 1 FROM pages WHERE notebook_id = n.id AND deleted = 0) OR
        EXISTS (SELECT 1 FROM recordings WHERE notebook_id = n.id AND deleted = 0) OR
        EXISTS (SELECT 1 FROM outline WHERE notebook_id = n.id AND deleted = 0) OR
        EXISTS (SELECT 1 FROM strokes WHERE surface_id = n.id AND deleted = 0) OR
        EXISTS (SELECT 1 FROM elements WHERE surface_id = n.id AND deleted = 0))''');
    for (final row in notebooks) {
      _reviveNotebook(row['id'] as String, _markOf(row), out);
    }
  }

  void _revivePage(String id, DeletionMark mark, Revival out) {
    final pages = notebooks.pages;
    pages.revive([id]);
    _reviveMarked(notebooks.strokes, 'surface_id = ?', [id], mark);
    final elements = notebooks.elements;
    if (elements != null) _reviveMarked(elements, 'surface_id = ?', [id], mark);
    if (notebooks.recognisedText case final text?) _reviveMarked(text, 'id = ?', [id], mark);
    out.surfaces.add(id);
    final notebook = pages.notebookOf(id);
    if (notebook != null) out.notebooks.add(notebook);
  }

  void _reviveNotebook(String id, DeletionMark mark, Revival out) {
    notebooks.revive([id]);
    if (notebooks.get(id) case final n? when n.trashedAt == null) notebooks.trash(id);
    final pageIds = _reviveMarked(notebooks.pages, 'notebook_id = ?', [id], mark);
    // Any page: one revived earlier may still miss content of this deletion.
    const surfaces =
        '(surface_id = ? OR surface_id IN (SELECT id FROM pages WHERE notebook_id = ?))';
    _reviveMarked(notebooks.strokes, surfaces, [id, id], mark);
    if (notebooks.elements case final elements?) {
      _reviveMarked(elements, surfaces, [id, id], mark);
    }
    if (notebooks.recordings case final recordings?) {
      _reviveMarked(recordings, 'notebook_id = ?', [id], mark);
    }
    if (notebooks.outline case final outline?) {
      _reviveMarked(outline, 'notebook_id = ?', [id], mark);
    }
    if (notebooks.recognisedText case final text?) {
      const ofSurfaces = '(id = ? OR id IN (SELECT id FROM pages WHERE notebook_id = ?))';
      _reviveMarked(text, ofSurfaces, [id, id], mark);
    }
    out.notebooks.add(id);
    out.surfaces
      ..add(id)
      ..addAll(pageIds);
  }

  /// Revives the rows of [table] matching [where] that deletion [mark]
  /// tombstoned; returns their ids.
  List<String> _reviveMarked(
    SyncableTable table,
    String where,
    List<Object?> args,
    DeletionMark mark,
  ) {
    final ids = [
      for (final row in _db.select(
        'SELECT id FROM ${table.table} '
        'WHERE deleted = 1 AND device_id = ? AND updated_at = ? AND $where',
        [mark.deviceId, mark.version, ...args],
      ))
        row['id'] as String,
    ];
    table.revive(ids);
    return ids;
  }

  static DeletionMark _markOf(Row row) =>
      (deviceId: row['device_id'] as String, version: row['updated_at'] as int);
}
