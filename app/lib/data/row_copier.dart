import 'package:sqlite3/common.dart';

/// Copies rows column-by-column, so copies stay complete even when later
/// migrations add columns (e.g. new page or stroke attributes).
class RowCopier {
  RowCopier(this._db);

  final CommonDatabase _db;

  /// What a copy's sync bookkeeping of rows edited in place starts as
  /// (`EditOrigins`): its own edit, no deletion's knowledge.
  static const fresh = <String, Object?>{
    'origin_at': null,
    'origin_device': null,
    'origin_for': 0,
    'base_at': null,
    'base_device': null,
  };
  final Map<String, List<String>> _columns = {};

  List<String> _columnsOf(String table) => _columns[table] ??= _db
      .select('PRAGMA table_info($table)')
      .map((r) => r['name'] as String)
      .toList();

  /// Inserts a copy of row [id] of [table] (a trusted constant), replacing
  /// the columns in [overrides] (which must include the new `id`). A copy
  /// is an edit of its own: it takes no origin or base (`EditOrigins`).
  void copy(String table, String id, Map<String, Object?> overrides) {
    assert(overrides.containsKey('id'), 'A copy needs a new id');
    final columns = _columnsOf(table);
    overrides = {
      for (final c in columns)
        if (fresh.containsKey(c)) c: fresh[c],
      ...overrides,
    };
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
