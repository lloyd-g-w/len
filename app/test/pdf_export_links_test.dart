import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/pdf_page_space.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';
import 'package:len/features/documents/export/pdf_export.dart';
import 'package:len/features/documents/export/vector/pdf_source_links.dart';
import 'package:len/features/documents/export/vector/pdf_source_reader.dart';
import 'package:len/features/documents/pdf/pdf_import.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdfrx/pdfrx.dart' show Pdfrx;

import 'pdf_rotation_test.dart' show a4, linkRect, rotatedPdf, shown;
import 'pdf_test.dart' show pdfium;
import 'support/pdf_fixtures.dart';

/// The links of every page of the PDF [bytes] (as Len's reader sees them).
List<List<PdfLinkArea>> linksOf(Uint8List bytes) {
  final pdf = PdfSourceReader.parse(bytes);
  return [
    for (var i = 0; i < pdf.pageCount; i++)
      readSourceLinks(pdf, i, pdf.pages[i].cropBox ?? pdf.pages[i].mediaBox!),
  ];
}

/// A notebook page showing page [index] of PDF blob 'src' (A4 turned by
/// [turns] quarter turns).
NotebookPage pdfPage(int index, int turns) {
  final size = turns.isOdd ? a4.flipped : a4;
  return NotebookPage(
    id: 'p$index',
    notebookId: 'n',
    sortKey: index.toDouble(),
    width: size.width * 96 / 72,
    height: size.height * 96 / 72,
    paper: const Paper(PaperStyle.blank),
    background: PageBackground.pdf(blob: 'src', pageIndex: index),
  );
}

Matcher near(Rect r) => rectMoreOrLessEquals(r, epsilon: 2e-3);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('source links: URI and GoTo targets, rects on turned pages', () async {
    final links = linksOf(await rotatedPdf([0, 1, 2, 3]));
    for (var turns = 0; turns < 4; turns++) {
      final web = links[turns].firstWhere((l) => l.url != null);
      expect(web.url, Uri.parse('https://example.com/'));
      expect(web.rects.single, near(shown(linkRect, turns)));
      expect(links[turns].firstWhere((l) => l.url == null).page, 0);
    }
  });

  test('source links: explicit and legacy destinations; other actions left out', () {
    final pdf = RawPdf('1.4');
    pdf.obj(1, '<< /Type /Catalog /Pages 2 0 R /Dests << /old [4 0 R /Fit] >> >>');
    pdf.obj(2, '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>');
    pdf.obj(
      3,
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /CropBox [0 0 200 100] '
      '/Annots [5 0 R 6 0 R 7 0 R 8 0 R] >>',
    );
    pdf.obj(4, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] >>');
    pdf.obj(5, '<< /Type /Annot /Subtype /Link /Rect [0 0 100 50] /Dest [4 0 R /XYZ 0 0 0] >>');
    pdf.obj(6, '<< /Type /Annot /Subtype /Link /Rect [100 50 200 100] /Dest /old >>');
    pdf.obj(
      7,
      '<< /Type /Annot /Subtype /Link /Rect [0 0 10 10] '
      '/A << /S /Launch /F (calc.exe) >> >>',
    );
    pdf.obj(8, '<< /Type /Annot /Subtype /Text /Rect [0 0 10 10] /Dest [4 0 R /Fit] >>');
    pdf.xrefTable('<< /Size 9 /Root 1 0 R >>');
    final links = linksOf(pdf.finish()).first;
    expect(links, hasLength(2));
    expect(links[0].page, 1);
    expect(links[0].rects.single, near(const Rect.fromLTRB(0, 0.5, 0.5, 1)));
    expect(links[1].page, 1);
    expect(links[1].rects.single, near(const Rect.fromLTRB(0.5, 0, 1, 0.5)));
  });

  test('copied PDF pages keep their links: web as is, page links remapped or dropped', () async {
    final source = PdfSourceReader.parse(await rotatedPdf([0, 1, 2, 3]));
    ExportPage page(int index) => ExportPage(
      pdfPage(index, index),
      const [],
      background: ExportBackground(source: source, pageIndex: index, raster: () async => null),
    );
    // Exported: source pages 2, 0 and 1 (so source page 0 becomes page 2);
    // source page 3 is left out.
    final out = linksOf(await PdfExporter.build([page(2), page(0), page(1)]));
    for (final (i, turns) in [(0, 2), (1, 0), (2, 1)]) {
      final web = out[i].singleWhere((l) => l.url != null);
      expect(web.url, Uri.parse('https://example.com/'));
      expect(web.rects.single, near(shown(linkRect, turns)));
      expect(out[i].singleWhere((l) => l.url == null).page, 1);
    }

    // Without source page 0, its page links are dropped.
    final partial = linksOf(await PdfExporter.build([page(3), page(1)]));
    expect(partial.map((p) => p.length), [1, 1]);
    expect(partial.expand((p) => p).every((l) => l.url != null), isTrue);
  });

  test('pages embedded as images get their links from PDFium\'s reading', () async {
    final out = linksOf(
      await PdfExporter.build([
        for (final i in [0, 1])
          ExportPage(
            pdfPage(i, 0),
            const [],
            background: ExportBackground(
              pageIndex: i,
              raster: () async => null,
              links: () async => [
                PdfLinkArea(const [Rect.fromLTRB(0.1, 0.2, 0.3, 0.4)], page: 1 - i),
                PdfLinkArea(const [
                  Rect.fromLTRB(0.5, 0.5, 0.6, 0.6),
                ], url: Uri.parse('https://a.b/')),
              ],
            ),
          ),
      ]),
    );
    expect(out[0].map((l) => l.page), [1, null]);
    expect(out[1].map((l) => l.page), [0, null]);
    expect(out[0].first.rects.single, near(const Rect.fromLTRB(0.1, 0.2, 0.3, 0.4)));
    expect(out[0].last.url, Uri.parse('https://a.b/'));
  });

  test('planner links become links between the exported planner pages', () async {
    NotebookPage planner(String id, Paper paper) =>
        NotebookPage(id: id, notebookId: 'n', sortKey: 0, width: 794, height: 1123, paper: paper);
    final month = planner(
      'm',
      Paper.planner(PaperStyle.monthlyCalendar, DateTime.utc(2026, 10, 1)),
    );
    final day = planner('d', Paper.planner(PaperStyle.dailyPlanner, DateTime.utc(2026, 10, 5)));
    final out = linksOf(
      await PdfExporter.build([ExportPage(month, const []), ExportPage(day, const [])]),
    );
    expect(out[0].map((l) => l.page), [1]); // October 5 on the month.
    expect(out[1].map((l) => l.page), [0]); // Back up to the month.
  });

  group('a notebook export', () {
    late Directory dir;
    late AppServices services;

    setUpAll(() {
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
      Pdfrx.pdfiumModulePath = pdfium;
    });
    setUp(() {
      dir = Directory.systemTemp.createTempSync('len_pdf_links_');
      services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
    });
    tearDown(() {
      services.dispose();
      dir.deleteSync(recursive: true);
    });

    test('keeps the links of its turned PDF pages', () async {
      final file = File('${dir.path}/in.pdf')..writeAsBytesSync(await rotatedPdf([0, 1, 2, 3]));
      final importer = PdfImporter(services);
      final nb = await importer.createNotebook(
        await importer.store(XFile(file.path)),
        title: 'PDF',
        cover: 0,
      );
      await importer.dispose();
      final pages = services.pages.pagesOf(nb.id);
      final exporter = NotebookExporter(services);
      final bytes = await exporter.pdf(pages.reversed.toList());
      await exporter.dispose();
      final out = linksOf(bytes);
      for (var i = 0; i < 4; i++) {
        final turns = 3 - i;
        expect(out[i].singleWhere((l) => l.url != null).rects.single, near(shown(linkRect, turns)));
        expect(out[i].singleWhere((l) => l.url == null).page, 3); // Source page 0, now last.
      }
    });
  }, skip: pdfium == null ? 'PDFium not built yet' : null);
}
