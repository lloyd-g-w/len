import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/features/documents/pdf/pdf_import.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_test.dart' show pdfium;
import 'support/pdf_fixtures.dart';

/// A PDF whose page tree holds [mediaBoxes] (one page each).
Uint8List _pdf(List<String> mediaBoxes) {
  final pdf = RawPdf();
  final kids = [for (var i = 0; i < mediaBoxes.length; i++) '${3 + i} 0 R'].join(' ');
  pdf.obj(1, '<< /Type /Catalog /Pages 2 0 R >>');
  pdf.obj(2, '<< /Type /Pages /Kids [$kids] /Count ${mediaBoxes.length} >>');
  for (var i = 0; i < mediaBoxes.length; i++) {
    pdf.obj(3 + i, '<< /Type /Page /Parent 2 0 R /MediaBox ${mediaBoxes[i]} >>');
  }
  pdf.xrefTable('<< /Size ${3 + mediaBoxes.length} /Root 1 0 R >>');
  return pdf.finish();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppServices services;

  setUpAll(() {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
  });
  setUp(() {
    dir = Directory.systemTemp.createTempSync('len_pdf_edge_');
    services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
  });
  tearDown(() {
    services.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<String> store(Uint8List bytes) =>
      PdfImporter(services).store(XFile.fromData(bytes, name: 'odd.pdf'));

  test('a PDF without pages is refused and creates nothing', skip: pdfium == null, () async {
    final importer = PdfImporter(services);
    final sha = await store(_pdf([]));
    await expectLater(
      importer.createNotebook(sha, title: 'Empty', cover: 0),
      throwsA(isA<FormatException>()),
    );
    expect(services.notebooks.list(), isEmpty);
    await importer.dispose();
  });

  test('degenerate page boxes become usable pages', skip: pdfium == null, () async {
    final importer = PdfImporter(services);
    final sha = await store(_pdf(['[0 0 0 0]', '[0 0 612 792]', '[0 0 -10 5]']));
    final notebook = await importer.createNotebook(sha, title: 'Odd', cover: 0);
    final pages = services.pages.pagesOf(notebook.id);
    expect(pages, hasLength(3));
    for (final p in pages) {
      expect(p.width, greaterThan(0));
      expect(p.height, greaterThan(0));
      expect(p.width.isFinite && p.height.isFinite, isTrue);
    }
    expect(pages[1].size.width, closeTo(612 * worldPerPoint, 0.01));
    // Every page record is valid for other devices.
    final records = services.pages.dirtyRecords(100).where((r) => !r.deleted);
    expect(records.every((r) => (r.data!['width'] as num) > 0), isTrue);
    await importer.dispose();
  });

  test('a file that is no PDF fails to read', skip: pdfium == null, () async {
    final importer = PdfImporter(services);
    final sha = await store(Uint8List.fromList('not a pdf at all'.codeUnits));
    await expectLater(importer.createNotebook(sha, title: 'Junk', cover: 0), throwsA(anything));
    expect(services.notebooks.list(), isEmpty);
    await importer.dispose();
  });
}
