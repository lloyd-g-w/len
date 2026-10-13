import 'package:sqlite3/common.dart';

import 'search/search_schema.dart';

/// What [AppDatabase] did when it found storage this build can't use (from
/// an older or newer pre-release Len, whose migrations differ): the old
/// file was kept aside at [backupPath] (null in a browser or in memory,
/// where it can't be) and Len started with an empty database.
class SchemaReset {
  const SchemaReset({this.backupPath, this.keptSync = false, this.fromNewer = false});

  final String? backupPath;

  /// Whether the storage came from a newer Len (else an older one).
  final bool fromNewer;

  /// Whether the sync server and token were carried over, so synced
  /// notebooks come back on their own.
  final bool keptSync;
}

/// Telling a usable database from one created by different migrations, and
/// replacing it (pre-release: no upgrade path, see CONVENTIONS.md).
abstract final class SchemaCheck {
  /// The settings carried over a reset: the sync login, so synced
  /// notebooks come back without asking (keys of `SettingsRepository`):
  /// the server, and the token's slot in the secure store or the token
  /// itself while it is kept in the database (`SyncTokenStore`).
  static const keptSettings = ['sync_url', 'sync_token_slot', 'sync_token'];

  /// Whether [kept] (from [reset]) holds a sync login.
  static bool keepsSync(Map<String, String> kept) =>
      kept.containsKey('sync_url') &&
      (kept.containsKey('sync_token_slot') || kept.containsKey('sync_token'));

  /// The structure the code relies on: every table with its columns (name,
  /// declared type, NOT NULL, primary key) and the names of indexes and
  /// triggers. The optional FTS index is left out (created when available).
  static Set<String> shapeOf(CommonDatabase db) {
    final shape = <String>{};
    final objects = db.select(
      "SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' "
      "AND type IN ('table', 'index', 'trigger', 'view')",
    );
    for (final o in objects) {
      final type = o['type'] as String;
      final name = o['name'] as String;
      if (SearchSchema.isFtsObject(name)) continue;
      if (type != 'table') {
        shape.add('$type $name');
        continue;
      }
      final columns = db
          .select('SELECT name, type, "notnull", pk FROM pragma_table_info(?) ORDER BY cid', [name])
          .map((c) => '${c['name']} ${c['type']} ${c['notnull']} ${c['pk']}');
      shape.add('table $name(${columns.join(', ')})');
    }
    return shape;
  }

  /// Whether [db] has no tables, indexes, triggers or views.
  static bool isEmpty(CommonDatabase db) =>
      db.select("SELECT 1 FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' LIMIT 1").isEmpty;

  /// Copies the database at [path] aside (`<path>.schema-<version>-<time>.bak`;
  /// skipped when [path] is null) and drops everything, leaving
  /// `user_version` 0. Returns the [keptSettings] found, to write back once
  /// the schema is created again.
  static (String?, Map<String, String>) reset(
    CommonDatabase db, {
    required String? path,
    required int version,
  }) {
    String? backup;
    if (path != null) {
      backup = '$path.schema-$version-${DateTime.now().millisecondsSinceEpoch}.bak';
      db.execute("VACUUM INTO '${backup.replaceAll("'", "''")}'");
    }
    final kept = <String, String>{};
    try {
      final rows = db.select(
        'SELECT key, value FROM settings WHERE key IN (${keptSettings.map((_) => '?').join(', ')})',
        keptSettings,
      );
      for (final r in rows) {
        if (r['value'] case final String value when value.isNotEmpty) {
          kept[r['key'] as String] = value;
        }
      }
    } on SqliteException {
      // No usable settings table: nothing to keep.
    }
    final objects = db.select(
      "SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' "
      "AND type IN ('table', 'view') "
      // Virtual tables first: dropping one drops its shadow tables, while
      // its constructor fails once they are gone.
      "ORDER BY sql LIKE 'CREATE VIRTUAL TABLE%' DESC, type DESC",
    );
    for (final o in objects) {
      final name = (o['name'] as String).replaceAll('"', '""');
      // Dropping a table drops its indexes and triggers (IF EXISTS skips
      // shadow tables already gone with their virtual table).
      db.execute('DROP ${o['type'] == 'view' ? 'VIEW' : 'TABLE'} IF EXISTS "$name"');
    }
    db.execute('PRAGMA user_version = 0');
    return (backup, kept);
  }
}
