import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive_io.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/archive/len_archives.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/features/backup/len_file_flows.dart';
import 'package:len/features/documents/export/export_options.dart';
import 'package:len/features/documents/import/import_router.dart';
import 'package:len/features/settings/backup_settings.dart';

AppServices _services() =>
    AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());

XFile _file(String name, {String? mime}) =>
    XFile.fromData(Uint8List(0), name: name, mimeType: mime, path: '/tmp/$name');

LenImportResult _result(LenArchiveKind kind, {int missing = 0, int skipped = 0}) => LenImportResult(
  manifest: LenManifest(
    kind: kind,
    title: kind == LenArchiveKind.library ? 'Library' : 'Lecture',
    createdAt: DateTime(2026, 10, 13, 9).millisecondsSinceEpoch,
  ),
  notebooks: const ['n'],
  folder: null,
  skipped: skipped,
  missingBlobs: missing,
);

void main() {
  group('Len files are recognised', () {
    test('by extension or MIME type, and imported as copies', () {
      expect(ImportRouter.kindOf(_file('Lecture.LEN')), IncomingKind.len);
      expect(ImportRouter.kindOf(_file('1000023', mime: LenFormat.mime)), IncomingKind.len);
      final plan = ImportRouter.plan([_file('a.len'), _file('b.pdf')]);
      expect(plan.steps.whereType<ImportLenFile>().single.file.name, 'a.len');
      expect(plan.unsupported, isEmpty);
    });
  });

  group('names and messages', () {
    test('file and folder names', () {
      expect(lenFileName('a/b: c'), endsWith('.len'));
      expect(backupFileName(DateTime(2026, 3, 4)), 'Len backup 2026-03-04.len');
      expect(backupFolderName(_result(LenArchiveKind.library).manifest), 'Backup 13 Oct 2026');
    });

    test('what an import says', () {
      expect(importedMessage(_result(LenArchiveKind.notebook)), 'Imported “Lecture”');
      expect(
        importedMessage(_result(LenArchiveKind.library, missing: 2, skipped: 1)),
        'Restored your backup into “Backup 13 Oct 2026”; 2 files were missing from it; '
        '1 item couldn’t be read',
      );
    });

    test('a Len export is always the whole notebook', () {
      const options = ExportOptions(format: ExportFormat.len, pages: [0, 1]);
      expect(options.summary, 'Whole notebook, Len file');
      expect(ExportFormat.len.mime, LenFormat.mime);
    });

    test('Settings says where notes are and when the last backup was', () {
      expect(
        BackupSettings.describe(syncing: false, android: false),
        startsWith('Your notes are kept only on this device.'),
      );
      expect(BackupSettings.describe(syncing: true, android: true), contains('Android backup'));
      final now = DateTime(2026, 10, 13, 18);
      expect(BackupSettings.lastBackup(null, now: now), endsWith('Not backed up yet'));
      int at(DateTime d) => d.millisecondsSinceEpoch;
      expect(BackupSettings.lastBackup(at(now), now: now), 'Backed up just now');
      expect(
        BackupSettings.lastBackup(at(DateTime(2026, 10, 13, 14, 5)), now: now),
        'Last backup today at 14:05',
      );
      expect(BackupSettings.lastBackup(at(DateTime(2026, 10, 3)), now: now), 'Last backup 3 Oct');
    });
  });

  test(
    'a library backup streams through files on disk and restores into a fresh library',
    () async {
      final dir = await Directory.systemTemp.createTemp('len-backup-test');
      addTearDown(() => dir.delete(recursive: true));
      final source = _services(), target = _services();
      addTearDown(source.dispose);
      addTearDown(target.dispose);
      final folder = source.folders.create(name: 'Physics', color: 1);
      for (var n = 0; n < 3; n++) {
        final notebook = source.notebooks.create(
          title: 'N$n',
          kind: NotebookKind.paged,
          paper: PaperStyle.blank,
          coverColor: 0,
        );
        source.notebooks.moveTo(notebook.id, folder.id);
        final page = source.pages.pagesOf(notebook.id).single;
        source.strokes.save([
          for (var i = 0; i < 50; i++)
            Stroke(
              id: 's$n-$i',
              surfaceId: page.id,
              tool: InkTool.ballpoint,
              color: 0xFF000000,
              width: 2,
              points: [StrokePoint(i.toDouble(), 1, 0.5), StrokePoint(i + 9.0, 4, 0.5)],
              createdAt: i,
            ),
        ]);
        final sha = await source.blobs.putBytes(Uint8List(64 * 1024)..[0] = n, mime: 'image/png');
        source.elements.save([
          SurfaceElement(
            id: 'img$n',
            surfaceId: page.id,
            type: 'image',
            rect: const Rect.fromLTWH(0, 0, 10, 10),
            rotation: 0,
            z: -1,
            createdAt: 1,
            data: ImageData(blob: sha, width: 10, height: 10).toJson(),
          ),
        ]);
      }
      final path = '${dir.path}/Len backup.len';
      final out = OutputFileStream(path);
      final report = await source.lenFiles.write(const LenScope.library(), out);
      await out.close();
      expect(report.blobs, 3);

      final input = InputFileStream(path);
      final result = await target.lenFiles.import(input, folderName: backupFolderName);
      await input.close();
      expect(result.manifest.kind, LenArchiveKind.library);
      final restored = target.folders.get(result.folder!)!;
      expect(restored.name, startsWith('Backup '));
      final physics = target.folders.childrenOf(restored.id).single;
      expect(physics.name, 'Physics');
      expect(result.notebooks, hasLength(3));
      for (final id in result.notebooks) {
        final notebook = target.notebooks.get(id)!;
        expect(notebook.folderId, physics.id);
        final page = target.pages.pagesOf(id).single;
        expect(SurfaceCopier(target.strokes).loadAll(page.id), hasLength(50));
        final image = SurfaceCopier(
          target.strokes,
          elements: target.elements,
        ).loadAllElements(page.id).single;
        final sha = ImageData.fromJson(image.data).blob;
        expect((await target.blobs.read(sha))!.length, 64 * 1024);
      }
    },
  );

  test('a file that is not a Len file says so', () async {
    final target = _services();
    addTearDown(target.dispose);
    await expectLater(
      target.lenFiles.import(InputMemoryStream(Uint8List.fromList([1, 2, 3]))),
      throwsA(isA<LenArchiveException>().having((e) => e.message, 'message', contains('Len file'))),
    );
  });
}
