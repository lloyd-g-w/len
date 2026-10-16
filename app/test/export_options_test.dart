import 'dart:convert';

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
  paperColor: PaperColor.presets.last,
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
      // Numbers too long for an int are out of range, not a crash.
      expect(parsePageRange('99999999999999999999999', 5).error, 'Pages are 1–5');
      expect(parsePageRange('1-99999999999999999999999', 5).error, 'Pages are 1–5');
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
        'a b c p1.png',
        'a b c p4.png',
      ]);
    });

    test('safe names', () {
      expect(safeFileName('  '), 'Notebook');
      expect(safeFileName('x?y*'), 'x y');
      // R22-5: one space where several were, no trailing dots, a length cap.
      expect(safeFileName('Physics: week 3/4'), 'Physics week 3 4');
      expect(safeFileName('Notes\t\n(draft)...'), 'Notes (draft)');
      expect(safeFileName('a' * 300), hasLength(maxFileNameBase));
    });

    test('Windows device names are not file names', () {
      for (final t in ['CON', 'nul', 'Aux', 'prn', 'COM1', 'lpt9', 'NUL.backup', 'con .x']) {
        final base = safeFileName(t).split('.').first.trimRight().toUpperCase();
        expect(RegExp(r'^(CON|PRN|AUX|NUL|COM\d|LPT\d)$').hasMatch(base), isFalse, reason: t);
      }
      expect(safeFileName('Contacts'), 'Contacts');
      expect(safeFileName('COM10'), 'COM10');
    });

    test('names fit file systems\' 255 bytes, whole characters kept', () {
      for (final title in ['漢' * 300, '😀' * 300, 'é' * 300, 'e\u0301' * 300]) {
        final name = exportFileNames(title, ExportFormat.pdf, [0, 2, 4], 9).single;
        expect(utf8.encode(name).length, lessThanOrEqualTo(255), reason: title.substring(0, 2));
        expect(utf8.decode(utf8.encode(name)), name); // No half of a surrogate pair.
        expect(name.endsWith('.pdf'), isTrue);
      }
      // A combining accent stays with its letter.
      final accented = safeFileName('e\u0301' * 300);
      expect(accented.endsWith('e\u0301'), isTrue);
    });

    test('a long page selection still makes a valid name', () {
      final odd = [for (var i = 0; i < 1000; i += 2) i];
      final name = exportFileNames('Physics', ExportFormat.pdf, odd, 1000).single;
      expect(utf8.encode(name).length, lessThanOrEqualTo(255));
      expect(name, startsWith('Physics '));
      expect(name, endsWith('.pdf'));
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
        '3 pages, PDF',
      );
      expect(
        const ExportOptions(format: ExportFormat.png, pages: [0]).summary,
        '1 page, PNG at 288 dpi',
      );
    });
  });
}
