import 'package:flutter/foundation.dart';
import 'package:sqlite3/common.dart';

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
  final List<SyncRecord> _templates = [];

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
      default:
        return _write(copy);
    }
    return true;
  }

  /// Adds the folders, templates and notebooks: those at the top of the
  /// file's tree go into [parent], or with [folderName] into a new folder
  /// there. Marks everything imported for sync. Returns the new notebooks,
  /// the folder holding the import, and how many records were malformed.
  ({List<String> notebooks, String? folder, int skipped}) finish({
    String? parent,
    String? folderName,
    int folderColor = 0,
  }) {
    var skipped = 0;
    final notebooks = <String>[];
    String? top;
    stores.any.database.transaction(() {
      var root = parent;
      if (folderName != null) {
        root = top = remap.clock.newId();
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
        } else if (placed.data!['parentId'] == root && folderName == null) {
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
      for (final (old, notebook) in _notebooks) {
        if (_write(_with(notebook, 'folderId', place(old)))) {
          notebooks.add(notebook.id);
        } else {
          skipped++;
        }
      }
      _markDirty();
    });
    return (notebooks: notebooks, folder: top, skipped: skipped);
  }

  /// Removes the content written so far (an import that failed or was
  /// cancelled); folders and notebooks were never written.
  void discard() {
    stores.any.database.transaction(() {
      _withIds(() {
        for (final table in ['strokes', 'stroke_chunks', 'elements', 'element_chunks']) {
          _db.execute('DELETE FROM $table WHERE surface_id IN $_surfaces');
        }
        for (final table in ['pages', 'outline', 'recordings']) {
          _db.execute('DELETE FROM $table WHERE notebook_id IN $_owners');
        }
      });
    });
  }

  void _markDirty() => _withIds(() {
    for (final table in ['folders', 'templates', 'notebooks']) {
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

  static SyncRecord _with(SyncRecord r, String field, String? value) => SyncRecord(
    collection: r.collection,
    id: r.id,
    updatedAt: r.updatedAt,
    deviceId: r.deviceId,
    deleted: false,
    data: {...?r.data, field: value},
  );
}
