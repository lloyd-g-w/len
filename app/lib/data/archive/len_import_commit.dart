import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/common.dart';

import '../../domain/notebook_style.dart';
import '../syncable.dart';
import '../syncable_table.dart';
import '../text_flow_relinks.dart';
import 'len_remap.dart';
import 'len_stores.dart';

/// Writes the records of a Len file being imported ([LenArchiveReader]):
/// content right away but clean (so sync leaves it alone) and under
/// notebooks that don't exist yet (so nothing shows it); folders, templates,
/// fonts and notebooks at [finish], in one transaction that also marks everything
/// for sync. [discard] removes what was written.
class LenImportCommit {
  LenImportCommit(this.stores, this.remap);

  final LenStores stores;
  final LenRemap remap;

  final List<(String, SyncRecord)> _folders = [], _notebooks = [];
  final List<SyncRecord> _templates = [], _fonts = [], _styles = [];

  /// The fonts [finish] added (marked for sync).
  final List<String> _addedFonts = [];

  /// The folder [finish] made to hold the import, if any.
  String? _holder;

  /// Tombstones of rows edited in place that the import wrote over (a
  /// restore keeping the ids of a notebook deleted here), as they were:
  /// table → their rows. [discard] puts them back.
  final Map<String, List<Row>> _overwritten = {};

  /// Rows edited in place that the import wrote where there were none
  /// (table → ids, of restores keeping ids only), which [discard] removes.
  final Map<String, List<String>> _added = {};

  CommonDatabase get _db => stores.any.db;

  /// Writes (or keeps for [finish]) [record], given new ids; false if it is
  /// malformed (null: not even a record) and was skipped.
  bool add(SyncRecord? record) {
    if (record == null) return false;
    final old = record.data?['parentId'] ?? record.data?['folderId'];
    final copy = remap.remap(record);
    // Tombstones and collections Len files don't hold are left out.
    if (copy == null) return true;
    switch (copy.collection) {
      case 'folders':
        _folders.add((old is String ? old : '', copy));
      case 'notebooks':
        _notebooks.add((old is String ? old : '', copy));
      case 'templates':
        _templates.add(copy);
      case 'fonts':
        _fonts.add(copy);
      case 'notebook_styles':
        _styles.add(copy);
      default:
        // Only a restore keeping ids writes over rows here.
        if (copy.id == record.id) _noteOverwritten(copy);
        return _write(copy);
    }
    return true;
  }

  /// Adds the folders, templates and notebooks: those at the top of the
  /// file's tree go into [parent], or with [folderName] into a new folder
  /// there (none when there is nothing to put in it). With
  /// [onlyUsedFolders] (notebooks were left out), folders that would hold
  /// no notebook are left out too. Marks everything imported for sync.
  /// Returns the new notebooks and folders, the folder holding the import,
  /// and how many records were malformed.
  ({List<String> notebooks, List<String> folders, String? folder, int skipped}) finish({
    String? parent,
    String? folderName,
    int folderColor = 0,
    bool onlyUsedFolders = false,
  }) {
    var skipped = 0;
    final notebooks = <String>[], folders = <String>[];
    String? top;
    if (onlyUsedFolders) _dropUnusedFolders();
    stores.any.database.transaction(() {
      var root = parent;
      if (folderName != null && (_folders.isNotEmpty || _notebooks.isNotEmpty)) {
        folders.add(remap.clock.newId());
        root = top = _holder = folders.last;
        _write(
          SyncRecord(
            collection: 'folders',
            id: root,
            updatedAt: remap.version,
            deviceId: remap.deviceId,
            deleted: false,
            data: {
              'name': folderName,
              'parentId': parent,
              'color': folderColor,
              'createdAt': remap.version,
            },
          ),
        );
      }
      final folderIds = {for (final (_, f) in _folders) f.id};
      String? place(String old) {
        final id = old.isEmpty ? null : remap.idOf(old);
        return folderIds.contains(id) ? id : root;
      }

      for (final (old, folder) in _folders) {
        final placed = _with(folder, 'parentId', place(old));
        if (!_write(placed)) {
          skipped++;
          continue;
        }
        folders.add(folder.id);
        if (placed.data!['parentId'] == root && folderName == null) {
          top ??= folder.id;
        }
      }
      for (final template in _templates) {
        final blob = template.data!['blob'];
        final known = _db.select('SELECT 1 FROM templates WHERE deleted = 0 AND blob = ?', [
          blob is String ? blob : '',
        ]).isNotEmpty;
        if (!known && !_write(template)) skipped++;
      }
      skipped += _addFonts();
      skipped += _addStyles();
      for (final (old, notebook) in _notebooks) {
        if (_write(_with(notebook, 'folderId', place(old)))) {
          notebooks.add(notebook.id);
        } else {
          skipped++;
        }
      }
      _dropBrokenFlows();
      _markDirty();
    });
    return (notebooks: notebooks, folders: folders, folder: top, skipped: skipped);
  }

  /// Text boxes continuing a box the file did not hold (or that was
  /// malformed) stand alone, their flow dropped, rather than continue a
  /// box that isn't there.
  void _dropBrokenFlows() {
    bool here(String id) =>
        _db.select('SELECT 1 FROM elements WHERE id = ? AND deleted = 0', [id]).isNotEmpty;
    for (final surface in remap.surfaces) {
      TextFlowRelinks.apply(_db, surface, (from) => here(from) ? from : null);
    }
  }

  /// Adds the fonts not here yet (a removed one comes back: its text is
  /// in the file). Returns how many were malformed.
  int _addFonts() {
    var skipped = 0;
    for (final font in _fonts) {
      final known = _db.select('SELECT 1 FROM fonts WHERE deleted = 0 AND id = ?', [font.id]);
      if (known.isNotEmpty) continue;
      // After a tombstone here, so the font comes back everywhere.
      final version = stores.of('fonts').nextVersion(font.id, font.updatedAt);
      if (_write(_stamped(font, version))) {
        _addedFonts.add(font.id);
      } else {
        skipped++;
      }
    }
    return skipped;
  }

  /// Adds the notebook styles but those already here (same name and
  /// style); an imported default stays one only where there is none yet.
  /// Returns how many were malformed.
  int _addStyles() {
    var skipped = 0;
    (String, NotebookChoice?) key(Object? name, Object? style) =>
        ('$name', style is Map<String, Object?> ? NotebookChoice.fromJson(style) : null);
    final here = {
      for (final row in _db.select('SELECT name, style FROM notebook_styles WHERE deleted = 0'))
        key(row['name'], jsonDecode(row['style'] as String)),
    };
    var hasDefault = _db
        .select('SELECT 1 FROM notebook_styles WHERE deleted = 0 AND is_default = 1')
        .isNotEmpty;
    for (final style in _styles) {
      final data = style.data!;
      final same = key(data['name'], data['style']);
      if (same.$2 != null && here.contains(same)) continue;
      final isDefault = data['isDefault'] == true && !hasDefault;
      if (_write(_with(style, 'isDefault', isDefault))) {
        here.add(same);
        hasDefault |= isDefault;
      } else {
        skipped++;
      }
    }
    return skipped;
  }

  /// Leaves out the folders that hold no notebook being imported, at any
  /// depth.
  void _dropUnusedFolders() {
    final parentOf = {for (final (old, f) in _folders) f.id: old.isEmpty ? null : remap.idOf(old)};
    final used = <String>{};
    for (final (old, _) in _notebooks) {
      String? id = old.isEmpty ? null : remap.idOf(old);
      while (id != null && parentOf.containsKey(id) && used.add(id)) {
        id = parentOf[id];
      }
    }
    _folders.removeWhere((entry) => !used.contains(entry.$2.id));
  }

  /// Removes the content written so far (an import that failed or was
  /// cancelled); folders and notebooks were never written.
  void discard() {
    stores.any.database.transaction(() {
      _withIds(() {
        _putBackOverwritten();
        _retombstone();
        for (final table in ['stroke_chunks', 'element_chunks']) {
          _db.execute('DELETE FROM $table WHERE surface_id IN $_surfaces');
        }
        for (final table in ['strokes', 'elements']) {
          _db.execute('DELETE FROM $table WHERE surface_id IN $_surfaces AND deleted = 0');
        }
        for (final table in ['pages', 'outline', 'recordings']) {
          _db.execute('DELETE FROM $table WHERE notebook_id IN $_owners AND deleted = 0');
        }
      });
    });
  }

  /// Keeps the tombstone [record] (a row edited in place, keeping its id)
  /// is about to be written over, or that there is no row yet, for
  /// [discard].
  void _noteOverwritten(SyncRecord record) {
    final table = stores.maybeOf(record.collection);
    if (table == null || !table.editedInPlace) return;
    final rows = _db.select('SELECT * FROM ${table.table} WHERE id = ?', [record.id]);
    if (rows.isEmpty) {
      (_added[table.table] ??= []).add(record.id);
    } else if (rows.single['deleted'] == 1) {
      (_overwritten[table.table] ??= []).add(rows.single);
    }
  }

  /// Puts back the tombstones of rows edited in place that the import
  /// wrote over, exactly as they were (version, content, what their
  /// deletion knew, the origin of what they kept), and removes those it
  /// wrote where there were none: a version must say the same everywhere,
  /// or this device would differ from the server for good (last-write-wins
  /// never replaces an equal version), so none may become a tombstone at
  /// the version of a deletion that its device may have pushed with
  /// another base ([_retombstone]). Rows changed since the import wrote
  /// them (a pull) are left alone.
  void _putBackOverwritten() {
    _added.forEach((table, ids) {
      for (final id in ids) {
        _db.execute(
          'DELETE FROM $table WHERE id = ? AND deleted = 0 AND updated_at = ? AND device_id = ?',
          [id, remap.version, remap.deviceId],
        );
      }
    });
    _overwritten.forEach((table, rows) {
      for (final row in rows) {
        final columns = [
          for (final c in row.keys)
            if (c != 'id') c,
        ];
        _db.execute(
          'UPDATE $table SET ${columns.map((c) => '$c = ?').join(', ')} '
          'WHERE id = ? AND deleted = 0 AND updated_at = ? AND device_id = ?',
          [for (final c in columns) row[c], row['id'], remap.version, remap.deviceId],
        );
        if (_db.updatedRows == 0) continue;
        // The deletion trigger noted the restore's version as what was
        // deleted: what the tombstone said instead.
        const noted = ['base_at', 'base_device', 'origin_at', 'origin_device', 'origin_for'];
        _db.execute('UPDATE $table SET ${noted.map((c) => '$c = ?').join(', ')} WHERE id = ?', [
          for (final c in noted) row[c],
          row['id'],
        ]);
      }
    });
  }

  /// A restore keeping the ids of notebooks deleted here wrote over their
  /// tombstones, whose deletion may not have synced yet: they become
  /// tombstones again, as the deletion left them (its device and version,
  /// see `DeletionConflicts`), rather than being removed. Rows edited in
  /// place are put back as they were first ([_putBackOverwritten]); where
  /// the restore wrote over one that was live here (content a pull brought
  /// that the deletion did not know), what the deletion knew is unknown
  /// (see `EditOrigins`) rather than the restore's version.
  void _retombstone() {
    final deleted = _db.select(
      'SELECT id, device_id, updated_at FROM notebooks '
      'WHERE deleted = 1 AND (id IN $_owners OR id IN $_surfaces)',
    );
    for (final row in deleted) {
      final mark = [row['device_id'], row['updated_at'], row['id']];
      const set = 'SET deleted = 1, dirty = 1, device_id = ?1, updated_at = ?2';
      for (final table in ['pages', 'outline', 'recordings']) {
        _db.execute('UPDATE $table $set WHERE notebook_id = ?3 AND deleted = 0', mark);
      }
      for (final table in ['strokes', 'elements']) {
        _db.execute(
          'UPDATE $table $set WHERE deleted = 0 AND '
          '(surface_id = ?3 OR surface_id IN (SELECT id FROM pages WHERE notebook_id = ?3))',
          mark,
        );
      }
    }
    // The deletion triggers noted the restore's rows as what was deleted.
    for (final table in SyncableTable.editedInPlaceCollections) {
      _db.execute(
        'UPDATE $table SET base_at = NULL, base_device = NULL, origin_at = NULL, '
        'origin_device = NULL, origin_for = 0 '
        'WHERE deleted = 1 AND base_at = ? AND base_device = ?',
        [remap.version, remap.deviceId],
      );
    }
  }

  void _markDirty() => _withIds(() {
    for (final table in ['folders', 'templates', 'fonts', 'notebook_styles', 'notebooks']) {
      _db.execute('UPDATE $table SET dirty = 1 WHERE id IN $_rows');
    }
    for (final table in ['pages', 'outline', 'recordings']) {
      _db.execute('UPDATE $table SET dirty = 1 WHERE notebook_id IN $_owners');
    }
    for (final table in ['strokes', 'elements']) {
      _db.execute('UPDATE $table SET dirty = 1 WHERE surface_id IN $_surfaces');
    }
  });

  static const _surfaces = "(SELECT id FROM temp.len_import WHERE kind = 's')";
  static const _owners = "(SELECT id FROM temp.len_import WHERE kind = 'o')";
  static const _rows = "(SELECT id FROM temp.len_import WHERE kind = 'r')";

  /// Runs [action] with the imported ids in `temp.len_import` (kind `s`:
  /// surfaces, `o`: notebooks owning pages and such, `r`: folders, templates
  /// and notebooks): any number of them, unlike SQL parameters.
  void _withIds(void Function() action) {
    _db.execute(
      'CREATE TEMP TABLE IF NOT EXISTS len_import (kind TEXT NOT NULL, id TEXT NOT NULL)',
    );
    _db.execute('DELETE FROM temp.len_import');
    final insert = _db.prepare('INSERT INTO temp.len_import (kind, id) VALUES (?, ?)');
    try {
      for (final id in remap.surfaces) {
        insert.execute(['s', id]);
      }
      for (final id in remap.owners) {
        insert.execute(['o', id]);
      }
      for (final id in [
        ?_holder,
        for (final (_, f) in _folders) f.id,
        for (final t in _templates) t.id,
        ..._addedFonts,
        for (final s in _styles) s.id,
        for (final (_, n) in _notebooks) n.id,
      ]) {
        insert.execute(['r', id]);
      }
    } finally {
      insert.close();
    }
    try {
      action();
    } finally {
      _db.execute('DROP TABLE temp.len_import');
    }
  }

  /// Writes [record] through its table's parser; false if malformed.
  bool _write(SyncRecord record) {
    try {
      stores.of(record.collection).writeRemote(record);
      return true;
    } on FormatException catch (e) {
      debugPrint('Skipping malformed ${record.collection}: ${e.message}');
    } on TypeError catch (e) {
      debugPrint('Skipping unreadable ${record.collection}: $e');
    } on ArgumentError catch (e) {
      debugPrint('Skipping unreadable ${record.collection}: $e');
    }
    return false;
  }

  static SyncRecord _stamped(SyncRecord r, int updatedAt) => SyncRecord(
    collection: r.collection,
    id: r.id,
    updatedAt: updatedAt,
    deviceId: r.deviceId,
    deleted: false,
    data: r.data,
  );

  static SyncRecord _with(SyncRecord r, String field, Object? value) => SyncRecord(
    collection: r.collection,
    id: r.id,
    updatedAt: r.updatedAt,
    deviceId: r.deviceId,
    deleted: false,
    data: {...?r.data, field: value},
  );
}
