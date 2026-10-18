import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:sqlite3/common.dart';

import '../platform/sqlite_connection.dart';

import 'schema_migrations.dart';
import 'schema_reset.dart';
import 'stepped_writes.dart';
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

  /// A second connection to the database file at [path], which the app's
  /// own connection opened (and migrated) already: for a worker isolate
  /// writing alongside it (see [transaction]). Native only.
  factory AppDatabase.attach(String path) =>
      AppDatabase._(openSqliteFile(path), path: path).._configure();

  /// Opens the app's own database `len.db` in [directory] — on the web it
  /// lives in IndexedDB instead, [directory] is ignored and the database
  /// joins [writes] (whose writes reach storage asynchronously).
  ///
  /// A new database, or one already in the current schema
  /// ([SchemaMigrations.shapeDigest]), opens without building a fresh
  /// schema to compare with; otherwise one is built first (browsers can't
  /// open a scratch database synchronously).
  static Future<AppDatabase> openDefault(String directory, {StorageWrites? writes}) async {
    final database = AppDatabase._(
      await openSqlite(name: _defaultName, directory: directory, writes: writes),
      path: sqliteFilePath(name: _defaultName, directory: directory),
    ).._configure();
    final version = database._version;
    final current = version == latestVersion && database._hasCurrentShape();
    // Compared with only when migrated from an older version or changed (a
    // new database, version 0, is created by the migrations).
    if (version > 0 && !current) _expected ??= _shapeOfFresh(await openSqliteScratch());
    return database.._migrate(shapeChecked: current);
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
  ///
  /// Transactions take the write lock when they begin (`IMMEDIATE`): with
  /// a second writer on the file (a pull applied in a worker, see
  /// [attach]), one that read first could otherwise not upgrade to
  /// writing once the other had committed (`SQLITE_BUSY`, which no waiting
  /// cures). Waiting for the other's transaction is bounded by
  /// [busyTimeoutMs].
  ///
  /// [steps] still running finish first.
  T transaction<T>(T Function() action) {
    if (_steps case final steps? when !steps.isRunning) steps.finish();
    if (!db.autocommit) return action();
    final signal = writeSignal?..begin();
    try {
      db.execute('BEGIN IMMEDIATE');
      try {
        final result = action();
        db.execute('COMMIT');
        return result;
      } catch (_) {
        // Some errors (a full disk, a trigger's RAISE(ROLLBACK)) roll back
        // already: a ROLLBACK then would hide them behind its own error.
        if (!db.autocommit) db.execute('ROLLBACK');
        rethrow;
      }
    } finally {
      signal?.end();
    }
  }

  /// Writes run in steps across turns, in one transaction (see
  /// [SteppedWrites]).
  SteppedWrites get steps => _steps ??= SteppedWrites(this);
  SteppedWrites? _steps;

  /// Told when this connection's transactions begin and end, while a
  /// second writer (a pull worker) yields to them.
  WriteSignal? writeSignal;

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

  /// Commits of this connection, and those [announceCommit] reports
  /// (another connection's, e.g. a worker applying a pull).
  Stream<void> get commits => _commits.stream;

  late final StreamController<void> _commits = StreamController<void>.broadcast(
    onListen: () => _ownCommits = db.commits.listen(_commits.add),
    onCancel: () {
      unawaited(_ownCommits?.cancel());
      _ownCommits = null;
    },
  );
  StreamSubscription<void>? _ownCommits;

  /// Tells [commits] listeners that another connection committed.
  void announceCommit() {
    if (_commits.hasListener) _commits.add(null);
  }

  /// How long a write waits for another connection's transaction before
  /// it fails (`waitWhenBusy`). Only a worker's slices (a few ms) and the
  /// app's own transactions contend.
  static const int busyTimeoutMs = 5000;

  /// Whether [close] was called.
  bool get isClosed => _closed;
  bool _closed = false;

  void close() {
    _steps?.finish();
    _closed = true;
    for (final statement in _statements.values) {
      statement.close();
    }
    _statements.clear();
    unawaited(_ownCommits?.cancel());
    _ownCommits = null;
    unawaited(_commits.close());
    db.close();
  }

  void _configure() {
    // First: another connection (a pull worker's, one closing and
    // checkpointing its log) may hold a lock that even the journal mode
    // waits for.
    waitWhenBusy(db, busyTimeoutMs);
    if (sqliteSupportsWal) {
      db.execute('PRAGMA journal_mode = WAL');
      // Shrinks the log back after large writes (an import), so it never
      // lingers at hundreds of MB (or fills Android's backup quota).
      db.execute('PRAGMA journal_size_limit = 4194304');
    }
    db.execute('PRAGMA foreign_keys = OFF');
    db.execute('PRAGMA synchronous = NORMAL');
    // 16 MB of page cache (default 2 MB): writing many rows at random ids
    // (a first sync) otherwise rereads index pages all the time.
    db.execute('PRAGMA cache_size = -16384');
  }

  /// [shapeChecked]: the schema is known to be current ([openDefault]).
  void _migrate({bool shapeChecked = false}) {
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
      if (schemaReset == null && !shapeChecked && !_hasExpectedShape()) {
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

  /// Whether the schema is exactly what the migrations produce.
  bool _hasCurrentShape() =>
      SchemaCheck.digestOf(SchemaCheck.shapeOf(db)) == SchemaMigrations.shapeDigest;

  /// Whether the schema has everything the migrations produce.
  bool _hasExpectedShape() {
    final shape = SchemaCheck.shapeOf(db);
    return SchemaCheck.digestOf(shape) == SchemaMigrations.shapeDigest ||
        shape.containsAll(_expectedShape());
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

/// Hears an [AppDatabase]'s transactions begin and end (see
/// [AppDatabase.writeSignal]).
abstract interface class WriteSignal {
  void begin();
  void end();
}
