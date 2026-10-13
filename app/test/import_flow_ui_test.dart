import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/features/documents/pdf/pdf_renderer.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/tabs/editor_workspace.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdfrx/pdfrx.dart';

import 'content_tools_ui_test.dart' show liveElements;
import 'images_test.dart' show pngOf;
import 'images_ui_test.dart' show settleReal;
import 'pdf_test.dart' show pdfium, samplePdf;
import 'ui_library_test.dart' show pumpLibrary;

/// Native `XFile.fromData` takes its name from [path].
XFile png(String name) =>
    XFile.fromData(pngOf(120, 80), name: name, path: '/tmp/$name', mimeType: 'image/png');

List<Notebook> notebooks(AppServices s) => s.notebooks.list();

/// Opens [notebook] in the editor from the library.
Future<void> openFromLibrary(WidgetTester tester, Notebook notebook) async {
  final context = tester.element(find.byType(Scaffold).first);
  unawaited(openNotebook(context, notebook));
  await tester.pumpAndSettle();
  expect(find.byType(EditorScreen), findsOneWidget);
}

void main() {
  testWidgets('images shared with nothing open become a new canvas, opened', (tester) async {
    final services = await pumpLibrary(tester);
    services.incomingFiles.add([png('IMG_2041.png')]);
    await settleReal(tester, () {
      final canvas = notebooks(services).where((n) => n.kind == NotebookKind.canvas).firstOrNull;
      return canvas != null && liveElements(services, canvas.id).isNotEmpty;
    });
    await tester.pumpAndSettle();
    final canvas = notebooks(services).single;
    expect(canvas.title, 'IMG 2041');
    expect(liveElements(services, canvas.id).single.knownType, ElementType.image);
    expect(find.byType(EditorScreen), findsOneWidget);
    expect(services.openNotebooks.activeId, canvas.id);
  });

  testWidgets('unsupported files get a friendly message and create nothing', (tester) async {
    final services = await pumpLibrary(tester);
    services.incomingFiles.add([XFile.fromData(Uint8List(3), path: '/tmp/notes.docx')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('“notes.docx” can’t be opened: Len opens PDFs and images.'), findsOneWidget);
    expect(notebooks(services), isEmpty);
  });

  testWidgets('with a canvas open, images can go into it (asked first)', (tester) async {
    final services = await pumpLibrary(tester);
    final board = services.notebooks.create(
      title: 'Board',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0xFF3B5BDB,
    );
    await openFromLibrary(tester, board);
    services.incomingFiles.add([png('a.png'), png('b.png')]);
    await tester.pumpAndSettle();
    expect(find.text('Open 2 files'), findsOneWidget);
    await tester.tap(find.text('Add to this canvas'));
    await settleReal(tester, () => liveElements(services, board.id).length == 2);
    await tester.pumpAndSettle();
    expect(notebooks(services), hasLength(1)); // No new notebook.
    expect(services.openNotebooks.activeId, board.id);
  });

  testWidgets('with a notebook open, "New canvas" opens the images in a new tab', (tester) async {
    final services = await pumpLibrary(tester);
    final lecture = services.notebooks.create(
      title: 'Lecture',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0xFF3B5BDB,
    );
    await openFromLibrary(tester, lecture);
    services.incomingFiles.add([png('scan.png')]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New canvas'));
    await settleReal(tester, () {
      final canvas = notebooks(services).where((n) => n.kind == NotebookKind.canvas).firstOrNull;
      return canvas != null && liveElements(services, canvas.id).isNotEmpty;
    });
    await tester.pumpAndSettle();
    final canvas = notebooks(services).firstWhere((n) => n.kind == NotebookKind.canvas);
    expect(services.openNotebooks.tabs.map((t) => t.id), [lecture.id, canvas.id]);
    expect(services.openNotebooks.activeId, canvas.id);
    expect(find.byType(EditorScreen), findsOneWidget); // Same workspace, no second route.
  });

  group('PDFs', () {
    late Directory dir;
    setUpAll(() async {
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
      Pdfrx.pdfiumModulePath = pdfium;
      // In real time, not in the first test's fake-async zone (which later
      // tests would then wait on).
      if (pdfium != null) await PdfRenderer.ensureInitialized();
    });
    setUp(() => dir = Directory.systemTemp.createTempSync('len_import_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    testWidgets('opened with nothing open: a new notebook', skip: pdfium == null, (tester) async {
      final services = AppServices.create(
        AppDatabase.inMemory(),
        blobBackend: FileBlobBackend(dir.path),
      );
      await pumpLibrary(tester, services: services);
      final file = (await tester.runAsync(() async {
        return File('${dir.path}/Lecture_3.pdf')..writeAsBytesSync(await samplePdf());
      }))!;
      services.incomingFiles.add([XFile(file.path)]);
      await settleReal(tester, () => services.openNotebooks.activeId != null);
      await tester.pumpAndSettle();
      final notebook = notebooks(services).single;
      expect(notebook.title, 'Lecture 3');
      expect(services.pages.pagesOf(notebook.id), hasLength(2));
      // Let PDFium finish rendering the pages before the editor goes.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a damaged PDF is refused and leaves no blob behind', skip: pdfium == null, (
      tester,
    ) async {
      final services = AppServices.create(
        AppDatabase.inMemory(),
        blobBackend: FileBlobBackend(dir.path),
      );
      await pumpLibrary(tester, services: services);
      final file = (await tester.runAsync(() async {
        return File('${dir.path}/broken.pdf')..writeAsStringSync('%PDF-1.7 not really');
      }))!;
      services.incomingFiles.add([XFile(file.path)]);
      final failure = find.textContaining('Couldn’t open “broken.pdf”');
      await settleReal(tester, () => failure.evaluate().isNotEmpty);
      expect(notebooks(services), isEmpty);
      expect(services.database.db.select('SELECT * FROM blobs'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('into the open notebook: pages after the current one', skip: pdfium == null, (
      tester,
    ) async {
      final services = AppServices.create(
        AppDatabase.inMemory(),
        blobBackend: FileBlobBackend(dir.path),
      );
      await pumpLibrary(tester, services: services);
      final lecture = services.notebooks.create(
        title: 'Lecture',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0xFF3B5BDB,
      );
      await openFromLibrary(tester, lecture);
      final file = (await tester.runAsync(() async {
        return File('${dir.path}/handout.pdf')..writeAsBytesSync(await samplePdf());
      }))!;
      services.incomingFiles.add([XFile(file.path)]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to this notebook'));
      await settleReal(tester, () => services.pages.pagesOf(lecture.id).length == 3);
      await tester.pumpAndSettle();
      expect(notebooks(services), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
