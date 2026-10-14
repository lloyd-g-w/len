import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/common.dart';

import '../../domain/notebook_style.dart';
import '../syncable.dart';
import 'len_remap.dart';
import 'len_stores.dart';

/// Writes the records of a Len file being imported ([LenArchiveReader]):
/// content right away but clean (so sync leaves it alone) and under
/// notebooks that don't exist yet (so nothing shows it); folders, templates
/// and notebooks at [finish], in one transaction that also marks everything
/// for sync. [discard] removes what was written.
class LenImportCommit {
  LenImportCommit(this.stores, this.remap);

  final LenStores stores;
  final LenRemap remap;

  final List<(String, SyncRecord)> _folders = [], _notebooks = [];
  final List<SyncRecord> _templates = [], _styles = [];

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
      case 'notebook_styles':
        _styles.add(copy);
      default:
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
        root = top = folders.last;
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
      skipped += _addStyles();
      for (final (old, notebook) in _notebooks) {
        if (_write(_with(notebook, 'folderId', place(old)))) {
          notebooks.add(notebook.id);
        } else {
          skipped++;
        }
      }
      _markDirty();
    });
    return (notebooks: notebooks, folders: folders, folder: top, skipped: skipped);
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

  /// A restore keeping the ids of notebooks deleted here wrote over their
  /// tombstones, whose deletion may not have synced yet: they become
  /// tombstones again, as the deletion left them (its device and version,
  /// see `DeletionConflicts`), rather than being removed.
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
  }

  void _markDirty() => _withIds(() {
    for (final table in ['folders', 'templates', 'notebook_styles', 'notebooks']) {
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
        for (final (_, f) in _folders) f.id,
        for (final t in _templates) t.id,
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

  static SyncRecord _with(SyncRecord r, String field, Object? value) => SyncRecord(
    collection: r.collection,
    id: r.id,
    updatedAt: r.updatedAt,
    deviceId: r.deviceId,
    deleted: false,
    data: {...?r.data, field: value},
  );
}
