import 'package:sqlite3/common.dart';

/// Copies rows column-by-column, so copies stay complete even when later
/// migrations add columns (e.g. new page or stroke attributes).
class RowCopier {
  RowCopier(this._db);

  final CommonDatabase _db;
  final Map<String, List<String>> _columns = {};

  List<String> _columnsOf(String table) => _columns[table] ??= _db
      .select('PRAGMA table_info($table)')
      .map((r) => r['name'] as String)
      .toList();

  /// Inserts a copy of row [id] of [table] (a trusted constant), replacing
  /// the columns in [overrides] (which must include the new `id`).
  void copy(String table, String id, Map<String, Object?> overrides) {
    assert(overrides.containsKey('id'), 'A copy needs a new id');
    final columns = _columnsOf(table);
    final values = [for (final c in columns) overrides.containsKey(c) ? '?' : c];
    _db.execute(
      'INSERT INTO $table (${columns.join(', ')}) '
      'SELECT ${values.join(', ')} FROM $table WHERE id = ?',
      [
        for (final c in columns)
          if (overrides.containsKey(c)) overrides[c],
        id,
      ],
    );
  }
}
