import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../syncable.dart';
import 'len_format.dart';
import 'len_stores.dart';

/// What to write into a Len file: one notebook, a folder (with everything
/// inside it), several notebooks or the whole library, the Trash aside.
class LenScope {
  const LenScope.notebook(String this.id) : kind = LenArchiveKind.notebook, ids = const [];
  const LenScope.folder(String this.id) : kind = LenArchiveKind.folder, ids = const [];
  const LenScope.notebooks(this.ids) : kind = LenArchiveKind.notebooks, id = null;
  const LenScope.library() : kind = LenArchiveKind.library, id = null, ids = const [];

  final LenArchiveKind kind;

  /// The notebook or folder; null for several notebooks and the library.
  final String? id;

  /// The notebooks of [LenScope.notebooks].
  final List<String> ids;
}

/// A [LenScope] resolved against the database: the folders and notebooks
/// it holds, the queries for their rows and how records are adjusted.
class ResolvedScope {
  ResolvedScope._(this.title, this.folders, this.notebooks, this._db, {required this.templates});

  /// Resolves [scope]; throws [StateError] if its notebook or folder is gone.
  factory ResolvedScope.of(LenScope scope, LenStores stores) {
    final db = stores.any.db;
    List<String> ids(String sql, [List<Object?> args = const []]) => [
      for (final r in db.select(sql, args)) r.columnAt(0) as String,
    ];
    switch (scope.kind) {
      case LenArchiveKind.notebook:
        final row = db.select('SELECT title FROM notebooks WHERE id = ? AND deleted = 0', [
          scope.id,
        ]).firstOrNull;
        if (row == null) throw StateError('The notebook no longer exists');
        return ResolvedScope._(row['title'] as String, const {}, [scope.id!], db, templates: false);
      case LenArchiveKind.folder:
        final row = db.select('SELECT name FROM folders WHERE id = ? AND deleted = 0', [
          scope.id,
        ]).firstOrNull;
        if (row == null) throw StateError('The folder no longer exists');
        final folders = _subtree(scope.id!, db);
        final notebooks = [
          for (final r in db.select(
            'SELECT id, folder_id FROM notebooks WHERE deleted = 0 AND trashed_at IS NULL '
            'ORDER BY id',
          ))
            if (folders.contains(r['folder_id'])) r['id'] as String,
        ];
        return ResolvedScope._(row['name'] as String, folders, notebooks, db, templates: false);
      case LenArchiveKind.notebooks:
        final live = {
          for (final r in db.select(
            'SELECT id FROM notebooks WHERE deleted = 0 AND trashed_at IS NULL',
          ))
            r['id'] as String,
        };
        final notebooks = [
          for (final id in {...scope.ids})
            if (live.contains(id)) id,
        ];
        if (notebooks.isEmpty) throw StateError('The notebooks no longer exist');
        final title = notebooks.length == 1 ? 'notebook' : 'notebooks';
        return ResolvedScope._(
          '${notebooks.length} $title',
          const {},
          notebooks,
          db,
          templates: false,
        );
      case LenArchiveKind.library:
        return ResolvedScope._(
          'Library',
          ids('SELECT id FROM folders WHERE deleted = 0').toSet(),
          // The Trash stays out (UX_AUDIT R8-23): a restore could purge it at once.
          ids('SELECT id FROM notebooks WHERE deleted = 0 AND trashed_at IS NULL ORDER BY id'),
          db,
          templates: true,
        );
    }
  }

  /// The notebook's or folder's title, "3 notebooks" for several,
  /// "Library" for the library.
  final String title;

  /// Folders written (their records keep their parents when in here).
  final Set<String> folders;

  /// Notebooks written.
  final List<String> notebooks;

  /// Whether the user's own templates, fonts and notebook styles are written (the
  /// library).
  final bool templates;

  final CommonDatabase _db;

  /// Live rows to write, roughly (for progress).
  late final int estimate = _estimate();

  /// For each collection in [LenFormat.collections] order, the SQL
  /// conditions (with their arguments) selecting this scope's rows.
  Iterable<(String, String, List<Object?>)> queries() sync* {
    if (folders.isNotEmpty) {
      for (final id in folders) {
        yield ('folders', 'id = ?', [id]);
      }
    }
    if (templates) {
      yield ('templates', '1', const []);
      yield ('fonts', '1', const []);
      yield ('notebook_styles', '1', const []);
    } else if (notebooks.isNotEmpty) {
      // The user fonts the notebooks' text uses (by id, as `font` or `f`).
      yield ('fonts', _fontsUsed, [jsonEncode(notebooks)]);
    }
    for (final id in notebooks) {
      yield ('notebooks', 'id = ?', [id]);
    }
    for (final collection in ['pages', 'outline', 'recordings']) {
      for (final id in notebooks) {
        yield (collection, 'notebook_id = ?', [id]);
      }
    }
    for (final collection in ['strokes', 'elements']) {
      for (final surface in _surfaces) {
        yield (collection, 'surface_id = ?', [surface]);
      }
    }
  }

  static const _fontsUsed = '''
    EXISTS (SELECT 1 FROM elements e
      WHERE e.deleted = 0 AND instr(e.data, '"' || fonts.id || '"') > 0
        AND (e.surface_id IN (SELECT value FROM json_each(?1))
          OR e.surface_id IN (SELECT p.id FROM pages p WHERE p.deleted = 0
            AND p.notebook_id IN (SELECT value FROM json_each(?1)))))''';

  /// Every surface of the notebooks: canvases are their own, pages theirs.
  late final List<String> _surfaces = [
    for (final id in notebooks) ...[
      id,
      for (final r in _db.select(
        'SELECT id FROM pages WHERE notebook_id = ? AND deleted = 0 ORDER BY sort_key, id',
        [id],
      ))
        r['id'] as String,
    ],
  ];

  /// [record] as written: a folder whose parent is not written, or a
  /// notebook whose folder is not, goes to the top of the file's tree.
  SyncRecord adjust(SyncRecord record) {
    final data = record.data;
    if (data == null) return record;
    final (field, kept) = switch (record.collection) {
      'folders' => ('parentId', folders.contains(data['parentId'])),
      'notebooks' => ('folderId', folders.contains(data['folderId'])),
      _ => ('', true),
    };
    if (kept || data[field] == null) return record;
    return SyncRecord(
      collection: record.collection,
      id: record.id,
      updatedAt: record.updatedAt,
      deviceId: record.deviceId,
      deleted: record.deleted,
      data: {...data, field: null},
    );
  }

  /// A few aggregate queries (per 500 notebooks), not one per page: a
  /// big library would freeze the UI before the first step (R8-19).
  int _estimate() {
    var n = folders.length + notebooks.length;
    for (var i = 0; i < notebooks.length; i += 500) {
      final ids = notebooks.sublist(i, (i + 500).clamp(0, notebooks.length));
      final marks = List.filled(ids.length, '?').join(', ');
      for (final table in ['pages', 'outline', 'recordings']) {
        n += _count(
          'SELECT COUNT(*) FROM $table WHERE deleted = 0 AND notebook_id IN ($marks)',
          ids,
        );
      }
      // Pages and canvases (their own surface).
      final surfaces =
          'surface_id IN (SELECT id FROM pages WHERE deleted = 0 AND notebook_id IN ($marks)) '
          'OR surface_id IN ($marks)';
      for (final table in ['strokes', 'elements']) {
        n += _count('SELECT COUNT(*) FROM $table WHERE deleted = 0 AND ($surfaces)', [
          ...ids,
          ...ids,
        ]);
      }
    }
    return n;
  }

  int _count(String sql, List<Object?> args) => _db.select(sql, args).first.columnAt(0) as int;

  /// [root] and the live folders nested in it.
  static Set<String> _subtree(String root, CommonDatabase db) {
    final children = <String, List<String>>{};
    for (final r in db.select('SELECT id, parent_id FROM folders WHERE deleted = 0')) {
      final parent = r['parent_id'] as String?;
      if (parent != null) (children[parent] ??= []).add(r['id'] as String);
    }
    final result = <String>{root};
    final queue = [root];
    while (queue.isNotEmpty) {
      for (final child in children[queue.removeLast()] ?? const <String>[]) {
        if (result.add(child)) queue.add(child);
      }
    }
    return result;
  }
}
