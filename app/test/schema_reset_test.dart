import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/schema_reset.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/data/sync_token_store.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/library/library_notice.dart';
import 'package:len/platform/secure_store.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

/// Storage left by a pre-release Len whose migrations were rewritten: the
/// current `user_version`, but a schema that differs.
void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('len_schema_reset_');
    path = '${dir.path}/len.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Creates a current database at [path] and lets [damage] change it; it
  /// holds one notebook, to tell old data from new.
  void prepare(void Function(AppDatabase) damage) {
    final services = AppServices.create(AppDatabase.open(path));
    services.notebooks.create(
      title: 'Old notes',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 1,
    );
    services.dispose();
    final raw = AppDatabase.open(path);
    damage(raw);
    raw.close();
  }

  List<String> backups() =>
      dir.listSync().map((f) => f.path).where((p) => p.contains('.schema-')).toList();

  int notebookCount(CommonDatabase db) =>
      db.select('SELECT count(*) AS n FROM notebooks').first['n'] as int;

  void expectFresh(AppDatabase db) {
    expect(db.db.select('PRAGMA user_version').first.columnAt(0), AppDatabase.latestVersion);
    final fresh = AppDatabase.inMemory();
    expect(SchemaCheck.shapeOf(db.db), SchemaCheck.shapeOf(fresh.db));
    fresh.close();
    expect(notebookCount(db.db), 0);
  }

  for (final (what, damage) in <(String, void Function(AppDatabase))>[
    ('a missing table', (d) => d.db.execute('DROP TABLE search_docs')),
    ('a missing column', (d) => d.db.execute('ALTER TABLE blobs DROP COLUMN rejected_limit')),
    (
      'an extra column',
      (d) => d.db.execute('ALTER TABLE pages ADD COLUMN old TEXT NOT NULL DEFAULT 0'),
    ),
    ('a missing trigger', (d) => d.db.execute('DROP TRIGGER ink_text_strokes_ai')),
  ]) {
    test('a current version with $what is backed up and reset', () {
      prepare(damage);
      final db = AppDatabase.open(path);
      addTearDown(db.close);
      expectFresh(db);
      final reset = db.schemaReset!;
      expect(reset.fromNewer, isFalse);
      expect(reset.keptSync, isFalse);
      expect(backups(), [reset.backupPath]);
      final old = sqlite3.open(reset.backupPath!);
      expect(notebookCount(old), 1, reason: 'the backup holds the old data');
      old.close();
    });
  }

  test('a migration that fails on an old schema resets too', () {
    prepare(
      (d) => d.db
        ..execute('DROP TABLE notebooks')
        ..execute('PRAGMA user_version = 6'), // Version 7 alters notebooks.
    );
    final db = AppDatabase.open(path);
    addTearDown(db.close);
    expectFresh(db);
    expect(db.schemaReset, isNotNull);
    expect(backups().single, contains('.schema-6-'));
  });

  test('tables at user_version 0 reset instead of failing', () {
    prepare((d) => d.db.execute('PRAGMA user_version = 0'));
    final db = AppDatabase.open(path);
    addTearDown(db.close);
    expectFresh(db);
    expect(db.schemaReset, isNotNull);
  });

  test('the sync login is kept, so synced notebooks come back', () async {
    final secure = MemorySecureStore();
    prepare((d) {
      SettingsRepository(d)
        ..syncUrl = 'https://len.example'
        ..syncLastSeq = 42;
    });
    final before = AppDatabase.open(path);
    await SyncTokenStore(SettingsRepository(before), secure).save('secret');
    before.db.execute('DROP TABLE outline');
    before.close();
    expect(secure.values.values, ['secret']);

    final db = AppDatabase.open(path);
    addTearDown(db.close);
    expect(db.schemaReset!.keptSync, isTrue);
    final settings = SettingsRepository(db);
    expect(settings.syncUrl, 'https://len.example');
    expect(settings.syncTokenFallback, isNull, reason: 'the token stays out of the database');
    final tokens = SyncTokenStore(settings, secure);
    await tokens.load();
    expect(tokens.token, 'secret');
    expect(settings.syncLastSeq, 0, reason: 'everything is pulled again');
  });

  test('a token kept in the database (no secure store) is kept too', () async {
    prepare((d) {
      SettingsRepository(d)
        ..syncUrl = 'https://len.example'
        ..syncTokenFallback = 'secret';
      d.db.execute('DROP TABLE outline');
    });
    final db = AppDatabase.open(path);
    addTearDown(db.close);
    expect(db.schemaReset!.keptSync, isTrue);
    final secure = MemorySecureStore();
    final tokens = SyncTokenStore(SettingsRepository(db), secure);
    expect(tokens.token, 'secret');
    await tokens.load();
    expect(secure.values.values, ['secret'], reason: 'moved to the secure store');
  });

  test('a matching database is untouched', () {
    prepare((_) {});
    final db = AppDatabase.open(path);
    addTearDown(db.close);
    expect(db.schemaReset, isNull);
    expect(notebookCount(db.db), 1);
    expect(backups(), isEmpty);
  });

  test('a new database is fine', () {
    final db = AppDatabase.open(path);
    addTearDown(db.close);
    expect(db.schemaReset, isNull);
    expectFresh(db);
    expect(backups(), isEmpty);
  });

  testWidgets('the library says so once, with the backup path to copy', (tester) async {
    prepare((d) => d.db.execute('DROP TABLE search_docs'));
    final services = AppServices.create(AppDatabase.open(path));
    addTearDown(services.dispose);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(
          home: Scaffold(body: LibraryNotices(child: SizedBox())),
        ),
      ),
    );
    expect(find.text('Len started fresh'), findsOneWidget);
    expect(find.textContaining('from an older version, so it started fresh'), findsOneWidget);
    final backup = services.database.schemaReset!.backupPath!;
    expect(find.widgetWithText(SelectableText, backup), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('Len started fresh'), findsNothing);
    expect(services.database.schemaReset, isNull);
  });
}
