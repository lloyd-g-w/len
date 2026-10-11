import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../domain/tag.dart';
import 'record_fields.dart';
import 'syncable.dart';
import 'syncable_table.dart';

/// Which tags are on which notebooks and pages (collection `taggings`).
///
/// One row per (tag, target) under a deterministic id ([idOf]), so tagging
/// the same notebook with the same tag on two devices converges on one
/// record, and removing a tag is a tombstone that a later re-add revives.
/// Tags on different targets, or different tags on one target, never
/// conflict.
class TaggingRepository extends SyncableTable {
  TaggingRepository(super.database, {required super.deviceId, super.clock});

  @override
  String get collection => 'taggings';

  @override
  String get table => 'taggings';

  static const _uuid = Uuid();

  /// The record id of tag [tagId] on [targetId]: a name-based (v5) UUID.
  static String idOf(String tagId, String targetId) =>
      _uuid.v5(Namespace.url.value, 'len:tagging/$tagId/$targetId');

  /// Live tag ids on [targetId] whose tag is live.
  Set<String> tagsOf(String targetId) => {
    for (final r in db.select(
      'SELECT g.tag_id FROM taggings g JOIN tags t ON t.id = g.tag_id AND t.deleted = 0 '
      'WHERE g.target_id = ? AND g.deleted = 0',
      [targetId],
    ))
      r['tag_id'] as String,
  };

  /// Every live tagging of [kind] whose tag is live: target id → tag ids.
  Map<String, Set<String>> all(TagTarget kind) {
    final result = <String, Set<String>>{};
    for (final r in db.select(
      'SELECT g.tag_id, g.target_id FROM taggings g '
      'JOIN tags t ON t.id = g.tag_id AND t.deleted = 0 '
      'WHERE g.kind = ? AND g.deleted = 0',
      [kind.name],
    )) {
      (result[r['target_id'] as String] ??= {}).add(r['tag_id'] as String);
    }
    return result;
  }

  /// Puts tag [tagId] on [targetId] ([on]) or takes it off.
  void set(String tagId, String targetId, TagTarget kind, {required bool on}) {
    final id = idOf(tagId, targetId);
    final rows = db.select('SELECT deleted FROM taggings WHERE id = ?', [id]);
    if (rows.isNotEmpty && (rows.first['deleted'] == 0) == on) return;
    if (rows.isEmpty && !on) return;
    db.execute(
      '''
      INSERT INTO taggings (id, tag_id, target_id, kind, updated_at, device_id, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, 1)
      ON CONFLICT(id) DO UPDATE SET deleted = excluded.deleted, dirty = 1,
        updated_at = excluded.updated_at, device_id = excluded.device_id''',
      [id, tagId, targetId, kind.name, nextVersion(id), deviceId, on ? 0 : 1],
    );
  }

  /// Makes [tagIds] exactly the tags on [targetId].
  void setTags(String targetId, TagTarget kind, Set<String> tagIds) => database.transaction(() {
    final current = tagsOf(targetId);
    for (final id in current.difference(tagIds)) {
      set(id, targetId, kind, on: false);
    }
    for (final id in tagIds.difference(current)) {
      set(id, targetId, kind, on: true);
    }
  });

  /// Takes tag [tagId] off everything (the tag was deleted).
  void removeTag(String tagId) => _tombstone(
    db
        .select('SELECT target_id FROM taggings WHERE tag_id = ? AND deleted = 0', [tagId])
        .map((r) => (tag: tagId, target: r['target_id'] as String)),
  );

  /// Takes every tag off [targetIds] (their notebook was deleted).
  void removeTargets(Iterable<String> targetIds) => database.transaction(() {
    for (final target in targetIds) {
      _tombstone([for (final tag in _liveTagIdsOf(target)) (tag: tag, target: target)]);
    }
  });

  /// Gives the copies the tags of their originals ([copies]: original id →
  /// copy id), e.g. when a notebook is duplicated.
  void copyTargets(Map<String, String> copies, TagTarget kind) => database.transaction(() {
    copies.forEach((from, to) {
      for (final tag in _liveTagIdsOf(from)) {
        set(tag, to, kind, on: true);
      }
    });
  });

  List<String> _liveTagIdsOf(String target) => [
    for (final r in db.select('SELECT tag_id FROM taggings WHERE target_id = ? AND deleted = 0', [
      target,
    ]))
      r['tag_id'] as String,
  ];

  void _tombstone(Iterable<({String tag, String target})> pairs) {
    for (final p in pairs.toList()) {
      final id = idOf(p.tag, p.target);
      db.execute(
        'UPDATE taggings SET deleted = 1, dirty = 1, updated_at = ?, device_id = ? WHERE id = ?',
        [nextVersion(id), deviceId, id],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Sync

  @override
  SyncRecord rowToRecord(Row row) {
    final deleted = row['deleted'] == 1;
    return SyncRecord(
      collection: collection,
      id: row['id'] as String,
      updatedAt: row['updated_at'] as int,
      deviceId: row['device_id'] as String,
      deleted: deleted,
      data: deleted
          ? null
          : {'tagId': row['tag_id'], 'targetId': row['target_id'], 'kind': row['kind']},
    );
  }

  @override
  void writeRemote(SyncRecord record) {
    if (record.deleted) {
      db.execute(
        '''
        INSERT INTO taggings (id, tag_id, target_id, kind, updated_at, device_id, deleted, dirty)
        VALUES (?, '', '', 'notebook', ?, ?, 1, 0)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at,
          device_id = excluded.device_id, deleted = 1, dirty = 0''',
        [record.id, record.updatedAt, record.deviceId],
      );
      return;
    }
    final f = RecordFields(record);
    final tagId = f.string('tagId'), targetId = f.string('targetId');
    final kind = f.choice('kind', TagTarget.values);
    if (record.id != idOf(tagId, targetId)) f.invalid('tagId');
    db.execute(
      '''
      INSERT OR REPLACE INTO taggings (id, tag_id, target_id, kind, updated_at, device_id,
                                       deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, 0, 0)''',
      [record.id, tagId, targetId, kind.name, record.updatedAt, record.deviceId],
    );
  }
}
