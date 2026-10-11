import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/export/export_options.dart';

NotebookPage _page(int i) => NotebookPage(
  id: 'p$i',
  notebookId: 'nb',
  sortKey: i.toDouble(),
  width: 794,
  height: 1123,
  paper: Paper(PaperStyle.gridLarge),
  paperColor: PaperColor.values.last,
);

void main() {
  group('parsePageRange', () {
    test('singles, spans and mixed separators, sorted and deduplicated', () {
      expect(parsePageRange('3', 5).pages, [2]);
      expect(parsePageRange('1-3, 5', 5).pages, [0, 1, 2, 4]);
      expect(parsePageRange(' 5 ;2–3, 2 ', 5).pages, [1, 2, 4]);
      expect(parsePageRange('4 - 4', 5).pages, [3]);
      expect(parsePageRange('1,,2,', 5).pages, [0, 1]);
    });

    test('explains bad input', () {
      expect(parsePageRange('', 5).error, contains('Enter pages'));
      expect(parsePageRange('  , ', 5).error, contains('Enter pages'));
      expect(parsePageRange('a', 5).error, contains('“a”'));
      expect(parsePageRange('1-', 5).error, contains('“1-”'));
      expect(parsePageRange('0', 5).error, 'Pages are 1–5');
      expect(parsePageRange('2-9', 5).error, 'Pages are 1–5');
      expect(parsePageRange('2', 1).error, 'Only page 1 exists');
      expect(parsePageRange('4-2', 5).error, contains('backwards'));
      expect(parsePageRange('4-2', 5).pages, isNull);
    });
  });

  test('formatPageRange compacts runs', () {
    expect(formatPageRange([0, 1, 2, 4]), '1-3,5');
    expect(formatPageRange([6]), '7');
    expect(formatPageRange([0, 2, 3], separator: ', '), '1, 3-4');
    expect(formatPageRange([]), '');
  });

  group('exportFileNames', () {
    test('PDF: the whole notebook, else the page range', () {
      expect(exportFileNames('Physics', ExportFormat.pdf, [0, 1, 2], 3), ['Physics.pdf']);
      expect(exportFileNames('Physics', ExportFormat.pdf, [0], 1), ['Physics.pdf']);
      expect(exportFileNames('Physics', ExportFormat.pdf, [1], 3), ['Physics p2.pdf']);
      expect(exportFileNames('Physics', ExportFormat.pdf, [0, 1, 4], 6), ['Physics p1-2,5.pdf']);
    });

    test('PNG: one file per page', () {
      expect(exportFileNames('a/b: c', ExportFormat.png, [0, 3], 4), [
        'a b  c p1.png',
        'a b  c p4.png',
      ]);
    });

    test('safe names', () {
      expect(safeFileName('  '), 'Notebook');
      expect(safeFileName('x?y*'), 'x y');
    });
  });

  group('ExportOptions', () {
    final pages = [for (var i = 0; i < 4; i++) _page(i)];

    test('resolve picks the pages, ignoring stale indices', () {
      const options = ExportOptions(format: ExportFormat.pdf, pages: [1, 3, 9]);
      expect(options.resolve(pages).map((p) => p.id), ['p1', 'p3']);
      expect(options.resolve(pages).first.paper.style, PaperStyle.gridLarge);
    });

    test('without templates pages become plain white paper', () {
      const options = ExportOptions(format: ExportFormat.png, pages: [0], includeTemplates: false);
      final page = options.resolve(pages).single;
      expect(page.paper.style, PaperStyle.blank);
      expect(page.paperColor, PaperColor.white);
      expect(page.id, 'p0');
      expect(page.size, pages[0].size);
    });

    test('summary', () {
      expect(
        const ExportOptions(format: ExportFormat.pdf, pages: [0, 1, 2]).summary,
        '3 pages · PDF',
      );
      expect(
        const ExportOptions(
          format: ExportFormat.png,
          pages: [0],
          pngResolution: PngResolution.high,
        ).summary,
        '1 page · PNG · 384 dpi',
      );
      expect(PngResolution.standard.dpi, 192);
    });
  });
}
