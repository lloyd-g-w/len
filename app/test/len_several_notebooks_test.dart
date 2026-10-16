import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/archive/len_archives.dart';
import 'package:len/features/backup/restore_dialogs.dart';
import 'package:len/features/documents/export/notebooks_export.dart';
import 'package:len/platform/file_export.dart';

import 'library_export_test.dart' show addPages;
import 'library_ui_test.dart' show addNotebook;

/// Several notebooks (a library selection) export as one Len file, and a
/// folder's "Export…" uses the same sheet.
void main() {
  test('a Len file of several notebooks imports them into the open folder', () async {
    final source = AppServices.create(AppDatabase.inMemory());
    addTearDown(source.dispose);
    final physics = source.folders.create(name: 'Physics', color: 1);
    final a = addNotebook(source, 'Optics', folderId: physics.id);
    final b = addNotebook(source, 'Waves');
    addNotebook(source, 'Left out');
    final out = OutputMemoryStream();
    await source.lenFiles.write(LenScope.notebooks([a.id, b.id, 'gone']), out);

    final target = AppServices.create(AppDatabase.inMemory());
    addTearDown(target.dispose);
    final here = target.folders.create(name: 'Here', color: 2);
    final opened = await target.lenFiles.open(InputMemoryStream(out.getBytes()));
    expect(opened.manifest.kind, LenArchiveKind.notebooks);
    expect(opened.manifest.title, '2 notebooks');
    final result = await target.lenFiles.import(opened, parent: here.id);
    expect(target.folders.list().map((f) => f.name), ['Here'], reason: 'no folders come along');
    final titles = {for (final id in result.notebooks) target.notebooks.get(id)!.title};
    expect(titles, {'Optics', 'Waves'});
    for (final id in result.notebooks) {
      expect(target.notebooks.get(id)!.folderId, here.id);
    }
    expect(importedMessage(result), 'Imported 2 notebooks');
  });

  group('the export sheet', () {
    late AppServices services;
    final exported = <(LenScope, String)>[];
    setUp(() {
      services = AppServices.create(AppDatabase.inMemory());
      exported.clear();
    });
    tearDown(() => services.dispose());

    Future<void> export(WidgetTester tester, List<String> titles, {bool folder = false}) async {
      final dir = services.folders.create(name: 'Term 1', color: 1);
      final notebooks = [for (final t in titles) addNotebook(services, t, folderId: dir.id)];
      addPages(services, notebooks.first, 2);
      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => exportNotebooks(
                    context,
                    notebooks,
                    folder: folder ? dir : null,
                    save: (files, {required mime, toDevice = false, subject}) async =>
                        ExportedFiles(ExportedTo.shared, count: files.length),
                    lenExport: (_, scope, {required name, toDevice = false}) async {
                      exported.add((scope, name));
                      return null;
                    },
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Len file'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers one Len file for several notebooks', (tester) async {
      await export(tester, ['Optics', 'Waves']);
      expect(find.text('2 notebooks, Len file'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('export-button')));
      await tester.pumpAndSettle();
      final (scope, name) = exported.single;
      expect(scope.kind, LenArchiveKind.notebooks);
      expect(scope.ids, hasLength(2));
      expect(name, '2 notebooks.len');
    });

    testWidgets('a folder’s Export… gives its Len file, or one PDF per notebook', (tester) async {
      await export(tester, ['Optics'], folder: true);
      expect(find.text('Term 1'), findsOneWidget); // The sheet's subtitle.
      expect(find.text('Pages'), findsNothing);
      expect(find.text('Whole folder, Len file'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('export-button')));
      await tester.pumpAndSettle();
      final (scope, name) = exported.single;
      expect(scope.kind, LenArchiveKind.folder);
      expect(name, 'Term 1.len');
    });
  });
}
