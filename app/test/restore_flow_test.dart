import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/archive/len_archives.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/backup/len_import_flow.dart';
import 'package:len/ui/app_theme.dart';

AppServices _services() =>
    AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());

/// The restore flow: asks first, lands where it should, offers Undo
/// (UX_AUDIT R8-15, R8-16); notebooks go into the open folder.
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

  Notebook notebook(AppServices s, String title, {String? folder}) => s.notebooks.create(
    title: title,
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0,
    folderId: folder,
  );

  Future<XFile> write(LenScope scope, String name) async {
    final out = OutputMemoryStream();
    await source.lenFiles.write(scope, out);
    return XFile.fromData(Uint8List.fromList(out.getBytes()), name: name);
  }

  Future<void> start(WidgetTester tester, XFile file) async {
    await tester.pumpWidget(
      AppScope(
        services: target,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => importLenFlow(context, file: file),
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
  }

  testWidgets('a restore asks first, goes into a dated folder and can be undone', (tester) async {
    notebook(source, 'Physics');
    notebook(target, 'Mine');
    final file = (await tester.runAsync(() => write(const LenScope.library(), 'backup.len')))!;
    await start(tester, file);

    expect(find.text('Restore this backup?'), findsOneWidget);
    expect(find.textContaining('holds 1 notebook.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pumpAndSettle();

    final restored = target.notebooks.list().singleWhere((n) => n.title == 'Physics');
    final folder = target.folders.get(restored.folderId!)!;
    expect(folder.name, startsWith('Backup '));
    expect(find.text('Restored your backup into “${folder.name}”'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(target.notebooks.list().single.title, 'Mine');
    expect(target.notebooks.trashed().single.title, 'Physics');
    expect(target.folders.list(), isEmpty);
  });

  testWidgets('cancelling the question restores nothing', (tester) async {
    notebook(source, 'Physics');
    final file = (await tester.runAsync(() => write(const LenScope.library(), 'backup.len')))!;
    await start(tester, file);
    expect(find.textContaining('They come back as they were.'), findsOneWidget); // Empty here.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(target.notebooks.list(), isEmpty);
  });

  testWidgets('restoring twice offers to skip what is here already', (tester) async {
    notebook(source, 'Physics');
    final file = (await tester.runAsync(() => write(const LenScope.library(), 'backup.len')))!;
    await start(tester, file);
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Restored your backup'), findsOneWidget);
    expect(target.notebooks.list().single.folderId, isNull); // At the top, as it was.

    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 of them is here already'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Skip those'));
    await tester.pumpAndSettle();
    expect(target.notebooks.list(), hasLength(1));
    expect(target.folders.list(), isEmpty);
  });

  testWidgets('a notebook goes into the library’s open folder', (tester) async {
    final n = notebook(source, 'Physics');
    final open = target.folders.create(name: 'Open', color: 0);
    target.lenFiles.openFolder = () => open.id;
    final file = (await tester.runAsync(() => write(LenScope.notebook(n.id), 'Physics.len')))!;
    await start(tester, file);
    expect(find.text('Imported “Physics”'), findsOneWidget);
    expect(target.notebooks.list().single.folderId, open.id);
  });
}
