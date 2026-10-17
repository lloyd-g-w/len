import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../../domain/notebook_version.dart';
import '../syncable.dart';
import '../syncable_table.dart';
import 'version_rows.dart';

/// What thinning needs to know of a version.
typedef VersionInfo = ({String id, int createdAt, VersionKind kind, int size});

/// The versions of notebooks (collection `versions`, docs/SYNC_PROTOCOL.md
/// "Version history"). A version's content is in packs (blobs); its row
/// keeps the whole record `data`.
class VersionRepository extends SyncableTable {
  VersionRepository(super.database, {required super.deviceId, super.clock});

  @override
  String get collection => 'versions';

  @override
  String get table => 'versions';

  /// The live versions of [notebookId], newest first.
  List<NotebookVersion> of(String notebookId) => [
    for (final row in db.select(
      'SELECT * FROM versions WHERE notebook_id = ? AND deleted = 0 '
      'ORDER BY created_at DESC, id DESC',
      [notebookId],
    ))
      ?_parse(row),
  ];

  /// A live version by id.
  NotebookVersion? get(String id) {
    final rows = db.select('SELECT * FROM versions WHERE id = ? AND deleted = 0', [id]);
    return rows.isEmpty ? null : _parse(rows.first);
  }

  /// The newest live version of [notebookId], if any.
  NotebookVersion? latest(String notebookId) {
    final rows = db.select(
      'SELECT * FROM versions WHERE notebook_id = ? AND deleted = 0 '
      'ORDER BY created_at DESC, id DESC LIMIT 1',
      [notebookId],
    );
    return rows.isEmpty ? null : _parse(rows.first);
  }

  /// How many live versions [notebookId] has.
  int countOf(String notebookId) =>
      db.select('SELECT COUNT(*) AS n FROM versions WHERE notebook_id = ? AND deleted = 0', [
            notebookId,
          ]).first['n']
          as int;

  /// What thinning needs of the live versions of [notebookId].
  List<VersionInfo> infosOf(String notebookId) => [
    for (final row in db.select(
      'SELECT id, created_at, kind, size FROM versions WHERE notebook_id = ? AND deleted = 0',
      [notebookId],
    ))
      (
        id: row['id'] as String,
        createdAt: row['created_at'] as int,
        kind: VersionKind.values.asNameMap()[row['kind']] ?? VersionKind.auto,
        size: row['size'] as int,
      ),
  ];

  /// Notebook id of a stored version (live or tombstoned), if known.
  String? notebookOf(String id) {
    final rows = db.select('SELECT notebook_id FROM versions WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.first['notebook_id'] as String;
  }

  /// Notebooks with live versions.
  List<String> notebooks() => [
    for (final row in db.select('SELECT DISTINCT notebook_id FROM versions WHERE deleted = 0'))
      row['notebook_id'] as String,
  ];

  /// Writes [version] as a local edit (a new one, or a rename).
  void save(NotebookVersion version) =>
      _write(version, updatedAt: nextVersion(version.id), deviceId: deviceId, dirty: true);

  /// Names version [id] (null: no name).
  void rename(String id, String? name) {
    final version = get(id);
    if (version == null) return;
    save(name == null ? version.copyWith(clearName: true) : version.copyWith(name: name));
  }

  /// Tombstones versions [ids].
  void delete(Iterable<String> ids) {
    final now = clock.nowMs();
    database.transaction(() {
      for (final id in ids) {
        db.execute(
          'UPDATE versions SET deleted = 1, dirty = 1, updated_at = ?, device_id = ? '
          'WHERE id = ? AND deleted = 0',
          [nextVersion(id, now), deviceId, id],
        );
      }
    });
  }

  NotebookVersion? _parse(Row row) {
    try {
      return VersionRows.fromRecord(rowToRecord(row));
    } on FormatException {
      return null; // Corrupt local data: as if absent.
    }
  }

  @override
  SyncRecord rowToRecord(Row row) {
    final deleted = row['deleted'] == 1;
    return SyncRecord(
      collection: collection,
      id: row['id'] as String,
      updatedAt: row['updated_at'] as int,
      deviceId: row['device_id'] as String,
      deleted: deleted,
      data: deleted ? null : jsonDecode(row['data'] as String) as Map<String, Object?>,
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      db.execute(
        '''
        INSERT INTO versions (id, notebook_id, created_at, kind, name, size, data,
                              updated_at, device_id, deleted, dirty)
        VALUES (?, '', 0, 'auto', NULL, 0, '{}', ?, ?, 1, 0)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at,
          device_id = excluded.device_id, deleted = 1, dirty = 0''',
        [record.id, record.updatedAt, record.deviceId],
      );
      return;
    }
    _write(
      VersionRows.fromRecord(record),
      updatedAt: record.updatedAt,
      deviceId: record.deviceId,
      dirty: false,
    );
  }

  void _write(
    NotebookVersion v, {
    required int updatedAt,
    required String deviceId,
    required bool dirty,
  }) => db.execute(
    '''
    INSERT OR REPLACE INTO versions (id, notebook_id, created_at, kind, name, size, data,
                                     updated_at, device_id, deleted, dirty)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)''',
    [
      v.id,
      v.notebookId,
      v.createdAt,
      v.kind.name,
      v.name,
      v.size,
      jsonEncode(v.toData()),
      updatedAt,
      deviceId,
      dirty ? 1 : 0,
    ],
  );
}
