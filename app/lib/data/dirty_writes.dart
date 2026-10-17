import 'app_database.dart';

/// Counts rows marked for upload (`dirty = 1`) by writes on this
/// connection: local edits, imports, revivals, a reset for a new server.
///
/// Sync uses it to push soon after local writes without being woken by
/// writes that need no upload (pulled records, search indexing, settings).
/// Temporary triggers (on this connection only, never in the file: a pull
/// worker's own connection writes without counting) bump a counter in a
/// temporary table, so it costs one small write per dirtied row.
class DirtyWrites {
  /// Installs the triggers on the syncable [tables] (trusted names).
  DirtyWrites(this.database, Iterable<String> tables) {
    database.transaction(() {
      final db = database.db
        ..execute('CREATE TEMP TABLE IF NOT EXISTS $_counter (n INTEGER NOT NULL)')
        ..execute('INSERT INTO $_counter SELECT 0 WHERE NOT EXISTS (SELECT 1 FROM $_counter)');
      for (final table in tables) {
        for (final event in const ['INSERT', 'UPDATE']) {
          db.execute(
            'CREATE TEMP TRIGGER IF NOT EXISTS len_dirty_${event.toLowerCase()}_$table '
            'AFTER $event ON main.$table WHEN NEW.dirty = 1 '
            'BEGIN UPDATE len_dirty_writes SET n = n + 1; END',
          );
        }
      }
    });
  }

  /// (Trigger bodies may not qualify table names: theirs is found in
  /// `temp` first.)
  static const _counter = 'temp.len_dirty_writes';

  final AppDatabase database;

  /// Rows dirtied on this connection so far (0 once the database closed).
  int get count =>
      database.isClosed ? 0 : database.select('SELECT n FROM $_counter').first['n'] as int;
}
