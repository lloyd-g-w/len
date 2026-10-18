import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/archive/len_archives.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/cancellation.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_style.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/backup/len_import_flow.dart';
import 'package:len/features/backup/restore_dialogs.dart';

AppServices _services() =>
    AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());

/// Restoring backups: as it was into an empty library, asking about what
/// is here already, and undoable (UX_AUDIT R8-15, R8-16).
void main() {
  late AppServices source, target;
  setUp(() {
    source = _services();
    target = _services();
  });
  tearDown(() {
    source.dispose();
    target.dispose();
  });

  Notebook notebook(AppServices s, String title, {String? folder}) {
    final n = s.notebooks.create(
      title: title,
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
      folderId: folder,
    );
    final page = s.pages.pagesOf(n.id).single;
    s.strokes.save([
      Stroke(
        id: 'ink-$title',
        surfaceId: page.id,
        tool: InkTool.ballpoint,
        color: 0xFF000000,
        width: 2,
        points: const [StrokePoint(1, 1, 0.5), StrokePoint(9, 4, 0.5)],
        createdAt: 1,
      ),
    ]);
    return n;
  }

  /// A library: "Physics" (in "School") and "Diary" (at the top).
  Future<Uint8List> backup() async {
    final school = source.folders.create(name: 'School', color: 1);
    notebook(source, 'Physics', folder: school.id);
    notebook(source, 'Diary');
    final out = OutputMemoryStream();
    await source.lenFiles.write(const LenScope.library(), out);
    return out.getBytes();
  }

  Future<LenSource> open(AppServices s, Uint8List bytes) =>
      s.lenFiles.open(InputMemoryStream(bytes));

  Future<LenImportResult> restore(
    AppServices s,
    Uint8List bytes, {
    String? folderName,
    Set<String> skip = const {},
  }) async =>
      s.lenFiles.import(await open(s, bytes), folderName: folderName, keepIds: true, skip: skip);

  test('into an empty library, a backup comes back as it was, same ids', () async {
    final bytes = await backup();
    final source0 = await open(target, bytes);
    expect(source0.contents.notebooks.values.toSet(), {'Physics', 'Diary'});
    expect(target.lenFiles.present(source0), isEmpty);
    await source0.close();

    final result = await restore(target, bytes);
    expect(
      {for (final n in target.notebooks.list()) n.id},
      {for (final n in source.notebooks.list()) n.id},
    );
    final school = target.folders.list().single;
    expect((school.name, school.parentId), ('School', null)); // Not nested in a backup folder.
    expect(school.id, source.folders.list().single.id);
    final physics = target.notebooks.list().singleWhere((n) => n.title == 'Physics');
    expect(physics.folderId, school.id);
    final page = target.pages.pagesOf(physics.id).single;
    expect(page.id, source.pages.pagesOf(physics.id).single.id);
    expect(SurfaceCopier(target.strokes).loadAll(page.id).single.id, 'ink-Physics');
    expect(result.folders, [school.id]);
  });

  test('restoring again asks about what is here: skip it, or copy it again', () async {
    final bytes = await backup();
    await restore(target, bytes);
    final again = await open(target, bytes);
    expect(target.lenFiles.present(again).values.toSet(), {'Physics', 'Diary'});

    // Skipping all of it adds nothing, not even an empty backup folder.
    final skipped = await target.lenFiles.import(
      again,
      folderName: 'Backup 13 Oct 2026',
      keepIds: true,
      skip: target.lenFiles.present(await open(target, bytes)).keys.toSet(),
    );
    expect(skipped.notebooks, isEmpty);
    expect(skipped.folders, isEmpty);
    expect(target.folders.list(), hasLength(1));
    expect(target.notebooks.list(), hasLength(2));
    // Nor the content of their pages (it once came as copies on no page).
    for (final table in ['strokes', 'elements']) {
      expect(
        target.database.db.select(
          'SELECT id FROM $table WHERE surface_id NOT IN (SELECT id FROM pages) '
          'AND surface_id NOT IN (SELECT id FROM notebooks)',
        ),
        isEmpty,
        reason: table,
      );
    }
    expect(target.database.db.select('SELECT id FROM strokes'), hasLength(2));

    // Restoring all of it again makes copies, in a folder of their own.
    final copies = await restore(target, bytes, folderName: 'Backup 13 Oct 2026');
    expect(copies.notebooks, hasLength(2));
    expect(target.notebooks.list(), hasLength(4));
    final backupFolder = target.folders.get(copies.folder!)!;
    expect(backupFolder.name, 'Backup 13 Oct 2026');
    expect(target.folders.childrenOf(backupFolder.id).single.name, 'School');
  });

  /// Strokes and elements of [s] on no page or canvas there.
  List<String> orphans(AppServices s) => [
    for (final table in ['strokes', 'elements'])
      for (final row in s.database.db.select(
        'SELECT id FROM $table WHERE deleted = 0 '
        'AND surface_id NOT IN (SELECT id FROM pages WHERE deleted = 0) '
        'AND surface_id NOT IN (SELECT id FROM notebooks WHERE deleted = 0)',
      ))
        '$table/${row['id']}',
  ];

  test(
    'a page that comes while a backup is written (synced in) is left out with its ink',
    () async {
      final n = notebook(source, 'Diary');
      final out = OutputMemoryStream();
      var turns = 0;
      await source.lenFiles.write(
        const LenScope.library(),
        out,
        drain: () async {
          // After the pages were read, before their ink is.
          if (++turns != 2) return;
          final page = source.pages.addPage(n.id);
          source.strokes.save([
            Stroke(
              id: 'late-ink',
              surfaceId: page.id,
              tool: InkTool.ballpoint,
              color: 0xFF000000,
              width: 2,
              points: const [StrokePoint(1, 1, 0.5), StrokePoint(9, 4, 0.5)],
              createdAt: 2,
            ),
          ]);
        },
      );
      expect(turns, greaterThan(2));
      final bytes = out.getBytes();
      final records = [
        for (final f in ZipDecoder().decodeBytes(bytes).files)
          if (f.name.startsWith(LenFormat.recordsPrefix)) utf8.decode(f.content as List<int>),
      ].join();
      expect(records, isNot(contains('late-ink')));
      await target.lenFiles.import(await open(target, bytes), folderName: 'Copy');
      expect(orphans(target), isEmpty);
      expect(target.database.db.select('SELECT id FROM strokes'), hasLength(1));
    },
  );

  test('ink on a page a file does not hold is left out of a restore', () async {
    final bytes = await backup();
    // The file without the record of Diary's page (as a backup written
    // while it came once held its ink alone).
    final diaryPage = source.pages.pagesOf(source.notebooks.list().last.id).single.id;
    final zip = ZipDecoder().decodeBytes(bytes);
    final edited = Archive();
    for (final file in zip.files) {
      if (!file.name.startsWith(LenFormat.recordsPrefix)) {
        edited.addFile(file);
        continue;
      }
      final lines = utf8.decode(file.content as List<int>).split('\n');
      final kept = lines.where(
        (l) => !(l.contains('"collection":"pages"') && l.contains('"id":"$diaryPage"')),
      );
      edited.addFile(ArchiveFile.string(file.name, kept.join('\n')));
    }
    final stripped = Uint8List.fromList(ZipEncoder().encode(edited));
    await restore(target, stripped);
    expect(orphans(target), isEmpty);
    expect(target.database.db.select('SELECT id FROM strokes'), hasLength(1));
  });

  test('on the device it came from, only what was deleted since comes back', () async {
    final bytes = await backup();
    final diary = source.notebooks.list().singleWhere((n) => n.title == 'Diary');
    final page = source.pages.pagesOf(diary.id).single.id;
    source.notebooks.delete(diary.id); // Deleted forever since the backup.

    final from = await open(source, bytes);
    final present = source.lenFiles.present(from);
    expect(present.values, ['Physics']);
    final result = await source.lenFiles.import(
      from,
      folderName: 'Backup 13 Oct 2026',
      keepIds: true,
      skip: present.keys.toSet(),
    );
    // The diary is back under its own id, with its ink; "School" (holding
    // only what was skipped) isn't copied.
    expect(result.notebooks, [diary.id]);
    final back = source.notebooks.get(diary.id)!;
    expect(back.folderId, result.folder);
    expect(source.pages.pagesOf(diary.id).single.id, page);
    expect(SurfaceCopier(source.strokes).loadAll(page).single.id, 'ink-Diary');
    expect(source.folders.list().map((f) => f.name).toSet(), {'School', 'Backup 13 Oct 2026'});
    expect(source.notebooks.list(), hasLength(2));
  });

  test(
    'a cancelled restore leaves a notebook deleted here deleted, its deletion still to sync',
    () async {
      final bytes = await backup();
      final diary = source.notebooks.list().singleWhere((n) => n.title == 'Diary');
      final page = source.pages.pagesOf(diary.id).single.id;
      source.notebooks.delete(diary.id); // Not synced yet.
      final db = source.pages.db;
      List<Object?> row(String table, String id) => [
        ...db.select('SELECT deleted, dirty, updated_at, device_id FROM $table WHERE id = ?', [id]),
      ].map((r) => r.values).toList();
      final before = [row('pages', page), row('strokes', 'ink-Diary')];
      expect(before.first, isNotEmpty);

      final from = await open(source, bytes);
      final cancel = CancellationToken();
      await expectLater(
        source.lenFiles.import(
          from,
          keepIds: true,
          skip: source.lenFiles.present(await open(source, bytes)).keys.toSet(),
          cancel: cancel,
          onProgress: (done) {
            if (done == 1) cancel.cancel(); // Everything written, not yet added.
          },
        ),
        throwsA(isA<Cancelled>()),
      );
      expect([row('pages', page), row('strokes', 'ink-Diary')], before);
      expect(source.notebooks.get(diary.id), isNull);
    },
  );

  test('restored under its own id, a notebook beats its deletion here, even one stamped later '
      '(another device\'s clock ahead)', () async {
    final bytes = await backup();
    final diary = source.notebooks.list().singleWhere((n) => n.title == 'Diary');
    final page = source.pages.pagesOf(diary.id).single.id;
    source.notebooks.delete(diary.id);
    final db = source.pages.db;
    final ahead = DateTime.now().millisecondsSinceEpoch + 3600 * 1000;
    for (final table in ['notebooks', 'pages', 'strokes']) {
      db.execute('UPDATE $table SET updated_at = ? WHERE deleted = 1', [ahead]);
    }

    final from = await open(source, bytes);
    await source.lenFiles.import(
      from,
      keepIds: true,
      skip: source.lenFiles.present(await open(source, bytes)).keys.toSet(),
    );
    int version(String table, String id) =>
        db.select('SELECT updated_at FROM $table WHERE id = ?', [id]).single['updated_at'] as int;
    expect(version('notebooks', diary.id), greaterThan(ahead));
    expect(version('pages', page), greaterThan(ahead));
    expect(version('strokes', 'ink-Diary'), greaterThan(ahead));
  });

  test('a backup holding notebook styles still tells what is here', () async {
    source.notebookStyles.create(
      name: 'Lecture',
      choice: const NotebookChoice(paper: PaperStyle.cornell, coverColor: 7),
    );
    final bytes = await backup();
    final from = await open(source, bytes);
    expect(from.contents.notebooks.values.toSet(), {'Physics', 'Diary'});
    expect(source.lenFiles.present(from).values.toSet(), {'Physics', 'Diary'});
  });

  test('the folder a restore goes into syncs like what it holds', () async {
    final bytes = await backup();
    await restore(target, bytes);
    final copies = await restore(target, bytes, folderName: 'Backup 13 Oct 2026');
    final dirty = {for (final r in target.folders.dirtyRecords(100)) r.id};
    expect(dirty, containsAll(copies.folders));
    expect(dirty, contains(copies.folder));
  });

  test('undo puts a restore in the Trash, its folders away', () async {
    final bytes = await backup();
    notebook(target, 'Mine');
    final result = await restore(target, bytes, folderName: 'Backup 13 Oct 2026');
    expect(target.notebooks.list(), hasLength(3));

    undoRestore(target, result);
    expect(target.notebooks.list().single.title, 'Mine');
    expect(target.notebooks.trashed().map((n) => n.title).toSet(), {'Physics', 'Diary'});
    expect(target.folders.list(), isEmpty);
    // Restorable: out of the Trash, at the top level.
    final physics = target.notebooks.trashed().firstWhere((n) => n.title == 'Physics');
    target.notebooks.restore(physics.id);
    expect(target.notebooks.get(physics.id)!.folderId, isNull);
  });

  test('the question says what a restore does', () {
    final manifest = LenManifest(
      kind: LenArchiveKind.library,
      title: 'Library',
      createdAt: DateTime(2026, 10, 13, 14, 5).millisecondsSinceEpoch,
    );
    expect(
      restoreQuestion(
        manifest: manifest,
        notebooks: 42,
        present: 0,
        intoEmpty: true,
        syncing: false,
      ),
      'The backup from 13 Oct 2026, 14:05 holds 42 notebooks. They come back as they were.',
    );
    expect(
      restoreQuestion(
        manifest: manifest,
        notebooks: 42,
        present: 3,
        intoEmpty: false,
        syncing: true,
      ),
      'The backup from 13 Oct 2026, 14:05 holds 42 notebooks. They are added in a folder of '
      'their own; nothing here is replaced. 3 of them are here already: skip those, or restore '
      'them again as copies? Everything restored syncs to your other devices too.',
    );
  });
}
