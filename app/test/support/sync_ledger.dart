import 'dart:convert';

import 'package:len/app_services.dart';

import 'package:len/data/syncable_table.dart';
import 'package:len/domain/notebook_version.dart';

import 'fault_devices.dart';

/// A row version: `updatedAt`, then `deviceId` (last-write-wins order).
typedef RowVersion = ({int at, String device});

bool _newer(RowVersion a, RowVersion b) =>
    a.at != b.at ? a.at > b.at : a.device.compareTo(b.device) > 0;

/// What the devices of a run wrote, to check against where sync ended:
/// every row's newest local write (which a converged state must hold, or
/// a newer one), the rows edits created and the rows they deleted, and the
/// points of every stroke as written.
class SyncLedger {
  /// `table/id` → the newest version any device wrote locally.
  final Map<String, RowVersion> newest = {};

  /// Rows that some edit made live (`table/id`).
  final Set<String> created = {};

  /// Rows some device deleted while it held them live (`table/id`): the
  /// user deleted them knowingly (themselves, or with their page,
  /// notebook or folder).
  final Set<String> deleted = {};

  /// Stroke id → its points as written (strokes are immutable).
  final Map<String, String> points = {};

  /// `table/id` → every live version devices wrote locally.
  final Map<String, List<RowVersion>> _edits = {};

  /// `table/id` of rows edited in place → what each live version written
  /// locally held (its record's `data`, as JSON).
  final Map<String, Map<RowVersion, String>> _contents = {};

  /// Rows deleted (alone or with their page or notebook): `table/id` → the
  /// versions the deleting devices knew.
  final Map<String, List<({RowVersion known})>> _deletions = {};

  /// Collections edited in place, whose edits a deletion that did not know
  /// them must not lose (docs/SYNC_PROTOCOL.md, "Deletion conflicts").
  static const _content = {'elements', 'recordings', 'outline'};

  /// Every synced row of [s]: `table/id` → (version, live).
  static Map<String, (RowVersion, bool)> snapshot(AppServices s) => {
    for (final table in syncedTables)
      for (final row in s.database.db.select(
        'SELECT id, updated_at, device_id, deleted FROM $table',
      ))
        '$table/${row['id']}': (
          (at: row['updated_at'] as int, device: row['device_id'] as String),
          row['deleted'] == 0,
        ),
  };

  /// What the versions [s] saved since [before] as the state before a
  /// restore hold (`table/id` of pages, strokes and elements): a restore
  /// removes what synced in while it ran, kept in that version.
  static Future<Set<String>> savedBeforeRestores(
    AppServices s,
    Map<String, (RowVersion, bool)> before,
  ) async {
    final out = <String>{};
    final versions = s.versions;
    for (final row in s.database.db.select('SELECT id FROM versions WHERE deleted = 0')) {
      final id = row['id'] as String;
      if (before.containsKey('versions/$id')) continue;
      final version = versions.store.get(id);
      if (version == null || version.kind != VersionKind.restore) continue;
      final body = await versions.content.body(version);
      for (final page in body.pages) {
        out.add('pages/${page.id}');
      }
      for (final surface in [for (final p in body.pages) p.content, ?body.canvas]) {
        for (final item in await versions.content.itemIds(surface)) {
          out.addAll(['strokes/$item', 'elements/$item']);
        }
      }
    }
    return out;
  }

  /// Records what one local edit on [s] did: [before] and the state now.
  /// [saved]: rows a restore of the edit kept in the version it saved
  /// before ([savedBeforeRestores]); deleting them deletes knowingly what
  /// the device held (which may have synced in during the edit). [after]:
  /// the state [snapshot] took when the edit ended (else now).
  void record(
    Map<String, (RowVersion, bool)> before,
    AppServices s, {
    Set<String> saved = const {},
    Map<String, (RowVersion, bool)>? after,
  }) {
    after ??= snapshot(s);
    for (final MapEntry(:key, value: (version, live)) in after.entries) {
      final old = before[key];
      if (old != null && old.$1 == version) continue;
      final known = newest[key];
      if (!live && saved.contains(key) && known != null) {
        deleted.add(key);
        _deletions.putIfAbsent(key, () => []).add((known: known));
      }
      if (known == null || _newer(version, known)) newest[key] = version;
      if (live) {
        _edits.putIfAbsent(key, () => []).add(version);
        if (_content.contains(key.split('/').first)) {
          _contents.putIfAbsent(key, () => {})[version] = content(s, key)!;
        }
      }
      if (!live && old != null && old.$2) {
        _deletions.putIfAbsent(key, () => []).add((known: old.$1));
      }
      final wasLive = old?.$2 ?? false;
      if (live && !wasLive) {
        created.add(key);
        if (key.startsWith('strokes/')) {
          final id = key.substring('strokes/'.length);
          final line = s.database.db.select(
            "SELECT surface_id, coalesce(json_extract(style, '\$.sh.o'), id) AS shape "
            "FROM strokes WHERE id = ? AND json_extract(style, '\$.sh.a') IS NOT NULL",
            [id],
          );
          if (line.isNotEmpty) {
            _lines[id] = (line.single['surface_id'] as String, line.single['shape'] as String);
          }
          points[id] = base64Encode(
            s.database.db.select('SELECT points FROM strokes WHERE id = ?', [id]).single['points']
                as List<int>,
          );
        }
      }
      if (!live && wasLive) deleted.add(key);
    }
  }

  /// Whether line [id] (deleted) was replaced by a connector repair
  /// (`ConnectorRepair`): it was attached, and another line of its shape
  /// id is on its surface (live, or deleted since with the page).
  bool _repaired(Iterable<AppServices> devices, String id) {
    final (surface, shape) = _lines[id] ?? (null, null);
    if (surface == null) return false;
    return devices.any(
      (s) => s.database.db.select(
        'SELECT 1 FROM strokes WHERE surface_id = ? AND id <> ? '
        "AND json_extract(style, '\$.sh.o') = ?",
        [surface, id, shape],
      ).isNotEmpty,
    );
  }

  /// Attached lines created: id → (surface, shape id).
  final Map<String, (String, String)> _lines = {};

  /// What live row [key] (`table/id`) of [s] holds: its record's data, as
  /// JSON; null if it is not live.
  static String? content(AppServices s, String key) {
    final [table, id] = key.split('/');
    final store = s.sync.engine.stores.whereType<SyncableTable>().firstWhere(
      (t) => t.table == table,
    );
    final rows = s.database.db.select('SELECT * FROM $table WHERE id = ? AND deleted = 0', [id]);
    return rows.isEmpty ? null : jsonEncode(store.rowToRecord(rows.single).data);
  }

  /// What [s] (a converged device) lost of what was written: rows behind
  /// a version some device wrote, rows created and never knowingly deleted
  /// that are not live, strokes whose points changed.
  /// [witnesses]: other devices, whose tombstones keep what they deleted.
  List<String> losses(AppServices s, {List<AppServices> witnesses = const []}) {
    final now = snapshot(s);
    final out = <String>[];
    for (final MapEntry(:key, value: version) in newest.entries) {
      final row = now[key];
      if (row == null) {
        out.add('$key: missing (written at ${version.at}/${version.device})');
      } else if (_newer(version, row.$1)) {
        out.add(
          '$key: at ${row.$1.at}/${row.$1.device}, written at ${version.at}/${version.device}',
        );
      }
    }
    // A row edited in place ends deleted only by a deletion that knew each
    // of its edits.
    for (final MapEntry(:key, value: edits) in _edits.entries) {
      if (!_content.contains(key.split('/').first) || (now[key]?.$2 ?? true)) continue;
      final deletions = _deletions[key] ?? const [];
      for (final edit in edits) {
        if (deletions.any((d) => !_newer(edit, d.known))) continue;
        out.add(
          '$key: edit ${edit.at}/${edit.device} lost to deletions knowing only '
          '${[for (final d in deletions) '${d.known.at}/${d.known.device}']}',
        );
      }
    }
    // A row edited in place that ends live holds the newest edit no
    // deletion knew, or a newer one: neither a copy brought back nor an
    // edit kept over a deletion replaces an edit it did not know.
    for (final MapEntry(:key, value: contents) in _contents.entries) {
      final now = content(s, key);
      if (now == null) continue;
      final deletions = _deletions[key] ?? const [];
      final unknown = [
        for (final edit in contents.keys)
          if (deletions.every((d) => _newer(edit, d.known))) edit,
      ];
      if (unknown.isEmpty) continue;
      final newest = unknown.reduce((a, b) => _newer(a, b) ? a : b);
      final holding = [
        for (final MapEntry(key: version, value: data) in contents.entries)
          if (data == now) version,
      ];
      if (holding.any((h) => !_newer(newest, h))) continue;
      out.add(
        '$key: edit ${newest.at}/${newest.device} lost; it holds what '
        '${holding.isEmpty ? 'no edit wrote' : [for (final h in holding) '${h.at}/${h.device}'].join(', ')} '
        'wrote',
      );
    }
    for (final key in created.difference(deleted)) {
      final stroke = key.startsWith('strokes/') ? key.substring('strokes/'.length) : null;
      if (stroke != null && _repaired([s, ...witnesses], stroke)) continue;
      if (now[key] case final row? when !row.$2) {
        out.add('$key: deleted at ${row.$1.at}/${row.$1.device}, but nobody deleted it knowingly');
      } else if (now[key] == null) {
        out.add('$key: missing, but nobody deleted it');
      }
    }
    for (final MapEntry(key: id, value: written) in points.entries) {
      final rows = s.database.db.select('SELECT points, deleted FROM strokes WHERE id = ?', [id]);
      if (rows.isEmpty || rows.single['deleted'] == 1) continue;
      if (base64Encode(rows.single['points'] as List<int>) != written) {
        out.add('strokes/$id: points changed');
      }
    }
    return out;
  }
}
