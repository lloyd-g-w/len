import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:sqlite3/common.dart';

import '../platform/sqlite_connection.dart';

import 'schema_migrations.dart';
import 'schema_reset.dart';
import 'write_back.dart';

/// Owns the SQLite connection and creates and migrates the schema (see
/// [SchemaMigrations]; `InitialSchema` lists the bookkeeping columns every
/// syncable table carries).
class AppDatabase {
  AppDatabase._(this.db, {this.path});

  /// Wraps an open connection to the file at [path] (null: in memory or
  /// in a browser), configuring it and applying migrations.
  factory AppDatabase.fromConnection(CommonDatabase db, {String? path}) =>
      AppDatabase._(db, path: path)
        .._configure()
        .._migrate();

  /// Opens (creating if needed) the database file at [path]. Native only.
  factory AppDatabase.open(String path) =>
      AppDatabase.fromConnection(openSqliteFile(path), path: path);

  /// Opens the app's own database `len.db` in [directory] — on the web it
  /// lives in IndexedDB instead, [directory] is ignored and the database
  /// joins [writes] (whose writes reach storage asynchronously).
  static Future<AppDatabase> openDefault(String directory, {StorageWrites? writes}) async {
    _expected ??= _shapeOfFresh(await openSqliteScratch());
    return AppDatabase.fromConnection(
      await openSqlite(name: _defaultName, directory: directory, writes: writes),
      path: sqliteFilePath(name: _defaultName, directory: directory),
    );
  }

  static const _defaultName = 'len.db';

  /// An in-memory database, for tests.
  factory AppDatabase.inMemory() => AppDatabase.fromConnection(openSqliteInMemory());

  final CommonDatabase db;

  /// The database file, or null for an in-memory (or browser) database.
  final String? path;

  /// Runs [action] inside a transaction, rolling back if it throws.
  ///
  /// Reentrant: when already inside a transaction, [action] simply joins it
  /// (an exception still propagates to, and rolls back, the outermost one).
  T transaction<T>(T Function() action) {
    if (!db.autocommit) return action();
    db.execute('BEGIN');
    try {
      final result = action();
      db.execute('COMMIT');
      return result;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Runs the query [sql] with [args] through a prepared statement kept
  /// for reuse. For constant SQL on hot paths (sync, chunk indexes):
  /// preparing a statement costs as much as running a small one.
  ResultSet select(String sql, [List<Object?> args = const []]) => _statement(sql).select(args);

  /// Like [select], for statements that return no rows.
  void execute(String sql, [List<Object?> args = const []]) => _statement(sql).execute(args);

  /// Prepared statements by their SQL, least recently used first.
  final _statements = <String, CommonPreparedStatement>{};

  /// How many prepared statements [select] and [execute] keep.
  static const _maxStatements = 64;

  CommonPreparedStatement _statement(String sql) {
    final cached = _statements.remove(sql);
    if (cached != null) return _statements[sql] = cached;
    if (_statements.length >= _maxStatements) {
      final oldest = _statements.keys.first;
      _statements.remove(oldest)!.close();
    }
    return _statements[sql] = db.prepare(sql, persistent: true);
  }

  /// Whether [close] was called.
  bool get isClosed => _closed;
  bool _closed = false;

  void close() {
    _closed = true;
    for (final statement in _statements.values) {
      statement.close();
    }
    _statements.clear();
    db.close();
  }

  void _configure() {
    if (sqliteSupportsWal) db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA foreign_keys = OFF');
    db.execute('PRAGMA synchronous = NORMAL');
  }

  void _migrate() {
    final version = _version;
    var kept = const <String, String>{};
    if (version > SchemaMigrations.all.length || (version == 0 && !SchemaCheck.isEmpty(db))) {
      kept = _reset(version);
    } else if (version > 0) {
      try {
        _upgrade(version);
      } on SqliteException catch (e) {
        debugPrint('Migrating the database from version $version failed: $e');
        kept = _reset(version);
      }
      if (schemaReset == null && !SchemaCheck.shapeOf(db).containsAll(_expectedShape())) {
        kept = _reset(version);
      }
    }
    _upgrade(_version);
    for (final MapEntry(:key, :value) in kept.entries) {
      db.execute('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [key, value]);
    }
  }

  int get _version => db.select('PRAGMA user_version').first.columnAt(0) as int;

  void _upgrade(int from) {
    for (var v = from; v < SchemaMigrations.all.length; v++) {
      transaction(() {
        SchemaMigrations.all[v](db);
        db.execute('PRAGMA user_version = ${v + 1}');
      });
    }
  }

  /// Set when this database was found with a schema this build can't use
  /// and was started afresh, until [acknowledgeSchemaReset] (the library
  /// tells the user once).
  SchemaReset? get schemaReset => _schemaReset;
  SchemaReset? _schemaReset;

  void acknowledgeSchemaReset() => _schemaReset = null;

  /// A database from a newer build, or one whose schema differs from what
  /// the migrations produce (they were rewritten pre-release), can't be
  /// used. Pre-release there is no upgrade path (see CONVENTIONS.md): the
  /// old file is kept aside (native only) and the database starts empty,
  /// instead of failing on missing tables or columns later.
  /// Returns the settings to write back ([SchemaCheck.keptSettings]).
  Map<String, String> _reset(int version) {
    final (backup, kept) = SchemaCheck.reset(db, path: path, version: version);
    _schemaReset = SchemaReset(
      backupPath: backup,
      keptSync: SchemaCheck.keepsSync(kept),
      fromNewer: version > SchemaMigrations.all.length,
    );
    debugPrint('Database schema (version $version) not usable; started fresh (backup: $backup)');
    return kept;
  }

  /// The shape of a freshly migrated database ([SchemaCheck.shapeOf]),
  /// computed once per run on a scratch in-memory database. [openDefault]
  /// prepares it asynchronously (browsers can't open one synchronously).
  static Set<String> _expectedShape() => _expected ??= _shapeOfFresh(openSqliteInMemory());
  static Set<String>? _expected;

  static Set<String> _shapeOfFresh(CommonDatabase scratch) {
    final fresh = AppDatabase.fromConnection(scratch);
    try {
      return SchemaCheck.shapeOf(fresh.db);
    } finally {
      fresh.close();
    }
  }

  /// The schema version of a fully migrated database.
  @visibleForTesting
  static int get latestVersion => SchemaMigrations.all.length;
}
