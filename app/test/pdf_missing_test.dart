import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/pdf/pdf_background_cache.dart';
import 'package:len/features/documents/pdf/pdf_renderer.dart';
import 'package:len/features/editor/chrome/missing_pdf_notice.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/editor_session.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:len/ui/app_theme.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import 'pdf_test.dart' show pdfium, samplePdf;
import 'support/real_async.dart';

/// A one-page PDF, different from [samplePdf].
Future<Uint8List> otherPdf({int pages = 2}) {
  final doc = pw.PdfDocument();
  for (var i = 0; i < pages; i++) {
    pw.PdfPage(doc, pageFormat: pw.PdfPageFormat.a5);
  }
  return doc.save();
}

String shaOf(Uint8List bytes) => sha256.convert(bytes).toString();

/// A notebook (as a PDF import makes it) whose two pages are drawn on
/// pages 0 and 1 of PDF [blob], which is not stored.
Notebook notebookOnMissingPdf(AppServices s, String blob) {
  final nb = s.notebooks.create(
    title: 'Handout',
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0,
  );
  final blank = s.pages.pagesOf(nb.id).single;
  s.pages.insertPages(nb.id, [
    for (final i in [0, 1])
      (
        size: const ui.Size(794, 1123),
        paper: Paper.blank,
        color: PaperColor.white,
        background: PageBackground.pdf(blob: blob, pageIndex: i),
      ),
  ]);
  s.pages.delete(blank.id);
  return nb;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppServices services;

  setUpAll(() async {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
    // Once per process, outside any test's zone: PDFium's replies then
    // reach every test, whichever zone it runs its work in.
    if (pdfium != null) await PdfRenderer.ensureInitialized();
  });
  setUp(() {
    dir = Directory.systemTemp.createTempSync('len_pdf_missing_test_');
    services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
  });
  tearDown(() {
    services.dispose();
    dir.deleteSync(recursive: true);
  });

  test('relinking points only the missing PDF\'s pages at the new one, page for page', () {
    final a = 'a' * 64, b = 'b' * 64, c = 'c' * 64;
    final nb = notebookOnMissingPdf(services, a);
    final other = services.pages.insertPages(nb.id, [
      (
        size: const ui.Size(794, 1123),
        paper: Paper.blank,
        color: PaperColor.white,
        background: PageBackground.pdf(blob: c, pageIndex: 4),
      ),
    ]).single;
    final changed = services.pages.relinkBackground(nb.id, from: a, to: b);
    expect(changed, hasLength(2));
    final pages = services.pages.pagesOf(nb.id);
    expect(pages.map((p) => p.background), [
      PageBackground.pdf(blob: b, pageIndex: 0),
      PageBackground.pdf(blob: b, pageIndex: 1),
      PageBackground.pdf(blob: c, pageIndex: 4),
    ]);
    expect(services.pages.get(other.id)!.background!.blob, c);
    // Synced like any other edit.
    expect(services.pages.referencedBlobs(), {b, c});
  });

  test('a PDF that cannot be fetched is reported missing until retried', () async {
    final fetched = <String>[];
    final cache = PdfBackgroundCache(
      blobs: services.blobs,
      fetch: (sha) async {
        fetched.add(sha);
        return false;
      },
    );
    addTearDown(cache.dispose);
    final bg = PageBackground.pdf(blob: 'd' * 64, pageIndex: 0);
    var notified = 0;
    cache.addListener(() => notified++);
    expect(cache.isMissing(bg), isFalse);
    expect(cache.imageFor(bg, 300), isNull);
    await pumpEventQueue();
    expect(cache.isMissing(bg), isTrue);
    expect(cache.missingBlobs, {'d' * 64});
    expect(notified, greaterThan(0));
    // Not asked for again while missing…
    cache.imageFor(bg, 300);
    await pumpEventQueue();
    expect(fetched, hasLength(1));
    // …until retried (e.g. after a sync).
    cache.retryMissing();
    expect(cache.isMissing(bg), isFalse);
    cache.imageFor(bg, 300);
    await pumpEventQueue();
    expect(fetched, hasLength(2));
  });

  test('a PDF fetched again says so (its text and links are read again)', () async {
    final fetched = <String>[];
    final cache = PdfBackgroundCache(
      blobs: services.blobs,
      fetch: (sha) async => sha != 'f' * 64,
      onFetched: fetched.add,
    );
    addTearDown(cache.dispose);
    cache
      ..imageFor(PageBackground.pdf(blob: 'e' * 64, pageIndex: 0), 300)
      ..imageFor(PageBackground.pdf(blob: 'f' * 64, pageIndex: 0), 300);
    await pumpEventQueue();
    expect(fetched, ['e' * 64]);
  });

  Future<Notebook> pumpMissing(WidgetTester tester, String blob) async {
    tester.view
      ..physicalSize = const Size(900, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final nb = notebookOnMissingPdf(services, blob);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: EditorScreen(notebook: nb),
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => find.byType(MissingPdfNotice).evaluate().isNotEmpty,
      reason: 'the missing PDF notice',
    );
    await pumpUntilPdfRendered(tester);
    return nb;
  }

  EditorSession session(WidgetTester tester) =>
      tester.widget<EditorCanvas>(find.byType(EditorCanvas)).session;

  testWidgets('pages of a missing PDF say so, and the editor offers Try again and Locate file', (
    tester,
  ) async {
    await pumpMissing(tester, 'e' * 64);
    expect(find.text('The PDF for these pages isn’t on this device'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Locate file…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // The notice fades in.
    await expectLater(find.byType(EditorScreen), matchesGoldenFile('goldens/pdf_missing.png'));

    // Dismissed, it stays away while the editor is open.
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byType(MissingPdfNotice), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('relinking the same file restores the PDF', skip: pdfium == null, (tester) async {
    final bytes = await samplePdf();
    final file = File('${dir.path}/handout.pdf')..writeAsBytesSync(bytes);
    await pumpMissing(tester, shaOf(bytes));
    expect(find.text('Locate file…'), findsOneWidget);
    final s = session(tester);
    await tester.runAsync(() async {
      await s.commands!.relinkPdf(
        tester.element(find.byType(MissingPdfNotice)),
        shaOf(bytes),
        s.pdfBackgrounds!,
        file: XFile(file.path),
      );
    });
    await pumpUntil(
      tester,
      () => s.pdfBackgrounds!.missingBlobs.isEmpty && find.text('Locate file…').evaluate().isEmpty,
      reason: 'the PDF to be found',
    );
    expect(s.pdfBackgrounds!.missingBlobs, isEmpty);
    expect(find.text('Locate file…'), findsNothing);
    expect(find.text('PDF found'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'relinking a different file asks first, then uses it page for page',
    skip: pdfium == null,
    (tester) async {
      final missing = 'f' * 64;
      final replacement = await otherPdf();
      final file = File('${dir.path}/again.pdf')..writeAsBytesSync(replacement);
      final nb = await pumpMissing(tester, missing);
      final s = session(tester);
      final context = tester.element(find.byType(MissingPdfNotice));
      // Runs in the test's zone; real file and PDFium work progresses while
      // [settle] waits in real time.
      var finished = false;
      final done = s.commands!
          .relinkPdf(context, missing, s.pdfBackgrounds!, file: XFile(file.path))
          .whenComplete(() => finished = true);
      Future<void> settle(bool Function() until) => pumpUntil(tester, until);

      await settle(() => find.text('Use a different PDF?').evaluate().isNotEmpty);
      expect(find.text('Use a different PDF?'), findsOneWidget);
      await tester.tap(find.text('Use this PDF'));
      await settle(() => finished);
      await done;
      await tester.pump();
      final sha = shaOf(replacement);
      expect(services.pages.pagesOf(nb.id).map((p) => p.background?.blob), [sha, sha]);
      expect(find.text('PDF relinked'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a PDF too short for the notes is refused', skip: pdfium == null, (tester) async {
    final missing = '0' * 64;
    final short = await otherPdf(pages: 1);
    final file = File('${dir.path}/short.pdf')..writeAsBytesSync(short);
    final nb = await pumpMissing(tester, missing);
    final s = session(tester);
    await tester.runAsync(
      () => s.commands!.relinkPdf(
        tester.element(find.byType(MissingPdfNotice)),
        missing,
        s.pdfBackgrounds!,
        file: XFile(file.path),
      ),
    );
    await tester.pump();
    expect(find.textContaining('has 1 page; these notes use page 2'), findsOneWidget);
    expect(services.pages.pagesOf(nb.id).map((p) => p.background?.blob), [missing, missing]);
    // The copied file isn't kept.
    expect(await tester.runAsync(() => services.blobs.has(shaOf(short))), isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
