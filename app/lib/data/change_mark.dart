import 'app_database.dart';

/// Marks of the stored state of pages or a notebook: two equal marks taken
/// at different times mean nothing was written there in between (no page,
/// stroke or element added, changed or deleted). Every local or synced
/// write bumps a row's `updated_at` or adds a row, so a mark is the row
/// counts and newest versions, tombstones included.
class ChangeMark {
  ChangeMark(this._database);

  final AppDatabase _database;

  /// The mark of pages [pageIds] with their strokes and elements.
  String pages(List<String> pageIds) {
    if (pageIds.isEmpty) return '';
    final marks = List.filled(pageIds.length, '?').join(', ');
    return [
      _of('SELECT COUNT(*) AS n, MAX(updated_at) AS v FROM pages WHERE id IN ($marks)', pageIds),
      _content('surface_id IN ($marks)', pageIds),
    ].join('|');
  }

  /// The mark of the pages of notebook [id] (also those added or deleted
  /// since) and their content.
  String notebook(String id) {
    const pages = 'SELECT id FROM pages WHERE notebook_id = ?';
    return [
      _of('SELECT COUNT(*) AS n, MAX(updated_at) AS v FROM pages WHERE notebook_id = ?', [id]),
      _content('surface_id IN ($pages)', [id]),
    ].join('|');
  }

  String _content(String where, List<Object?> args) => [
    for (final table in ['strokes', 'elements'])
      _of('SELECT COUNT(*) AS n, MAX(updated_at) AS v FROM $table WHERE $where', args),
  ].join('|');

  String _of(String sql, List<Object?> args) {
    final row = _database.db.select(sql, args).first;
    return '${row['n']}:${row['v']}';
  }
}
