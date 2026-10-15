import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/page_repository.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/pdf_page_numbers.dart';

const _deck = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _paper = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _deck2 = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

const _slide = Size(960, 540);
const _a4 = Size(595, 842);

/// A page showing page [pdfPage] (zero-based) of [blob], or a notes page.
NotebookPage _page(int i, {String? blob, int pdfPage = 0, Size size = _slide}) => NotebookPage(
  id: 'p$i',
  notebookId: 'n',
  sortKey: i.toDouble(),
  width: size.width,
  height: size.height,
  paper: Paper.blank,
  background: blob == null ? null : PageBackground.pdf(blob: blob, pageIndex: pdfPage),
);

/// Pages 1–2 slides 1–2, page 3 notes, pages 4–5 slides 3–4 (a lecture
/// with a notes page added after slide 2).
List<NotebookPage> _lecture() => [
  _page(0, blob: _deck, pdfPage: 0),
  _page(1, blob: _deck, pdfPage: 1),
  _page(2),
  _page(3, blob: _deck, pdfPage: 2),
  _page(4, blob: _deck, pdfPage: 3),
];

void main() {
  test('labels only where the PDF page number differs; slides when landscape', () {
    final numbers = PdfPageNumbers(_lecture());
    expect(
      [for (var i = 0; i < 5; i++) numbers.labelOf(i)],
      [null, null, null, 'Slide 3', 'Slide 4'],
    );
    expect(numbers.pdfNumberOf(3), 3);
    expect(numbers.pdfNumberOf(2), isNull);
    expect(numbers.hasLabels, isTrue);
  });

  test('a plain import has no labels; a portrait PDF says "PDF p."', () {
    final plain = PdfPageNumbers([
      for (var i = 0; i < 3; i++) _page(i, blob: _paper, pdfPage: i, size: _a4),
    ]);
    expect(plain.hasLabels, isFalse);
    final cover = PdfPageNumbers([
      _page(0),
      for (var i = 0; i < 2; i++) _page(i + 1, blob: _paper, pdfPage: i, size: _a4),
    ]);
    expect(cover.labelOf(1), 'PDF p. 1');
    expect(cover.labelOf(2), 'PDF p. 2');
  });

  test('"s23", "slide 23" and "pdf p. 23" name PDF page 23; numbers do not', () {
    for (final text in ['s23', 'S 23', 'slide 23', 'Slide23', 'pdf 23', 'PDF p. 23', ' s23 ']) {
      expect(PdfPageNumbers.parse(text), 23, reason: text);
    }
    for (final text in ['23', 'x23', 'slides', 's', 'page 23', 's-1']) {
      expect(PdfPageNumbers.parse(text), isNull, reason: text);
    }
  });

  test('find: a slide in one PDF is one page', () {
    final numbers = PdfPageNumbers(_lecture());
    expect(numbers.find(3), [3]);
    expect(numbers.find(9), isEmpty);
  });

  test('find: several PDFs ask, unless the current page belongs to one', () {
    // Deck 1 (pages 1–2), notes (3), deck 2 (pages 4–5), a duplicate of
    // deck 2's first slide (6).
    final pages = [
      _page(0, blob: _deck, pdfPage: 0),
      _page(1, blob: _deck, pdfPage: 1),
      _page(2),
      _page(3, blob: _deck2, pdfPage: 0),
      _page(4, blob: _deck2, pdfPage: 1),
      _page(5, blob: _deck2, pdfPage: 0),
    ];
    final numbers = PdfPageNumbers(pages);
    // No current page: both PDFs' first such page, in order.
    expect(numbers.find(1), [0, 3]);
    // On a page of a PDF: that PDF's page wins.
    expect(numbers.find(1, current: 1), [0]);
    expect(numbers.find(2, current: 5), [4]);
    // A notes page belongs to the PDF before it.
    expect(numbers.find(1, current: 2), [0]);
    // The current page's PDF lacks it: the others' are offered.
    final more = PdfPageNumbers([...pages, _page(6, blob: _paper, pdfPage: 2, size: _a4)]);
    expect(more.find(3, current: 0), [6]);
    expect(more.find(1, current: 6), [0, 3]);
  });

  test('Replace PDF… keeps the numbers: pages follow the new PDF', () {
    final s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'L',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    PageSpec slide(String blob, int i) => (
      size: _slide,
      paper: Paper.blank,
      color: PaperColor.white,
      background: PageBackground.pdf(blob: blob, pageIndex: i),
    );
    // The lecture's slides replace the notebook's first, blank page.
    s.pages.delete(s.pages.pagesOf(nb.id).single.id);
    final first = s.pages.insertPages(nb.id, [slide(_deck, 0), slide(_deck, 1)]);
    s.pages.addPage(nb.id, template: const PageTemplate(), after: first.last);
    s.pages.insertPages(nb.id, [slide(_deck, 2)]);
    expect(PdfPageNumbers(s.pages.pagesOf(nb.id)).labelOf(3), 'Slide 3');

    // The new version of the deck has a fourth slide, added at the end.
    s.pages.relinkBackground(nb.id, from: _deck, to: _deck2);
    s.pages.insertPages(nb.id, [slide(_deck2, 3)]);
    final numbers = PdfPageNumbers(s.pages.pagesOf(nb.id));
    expect(
      [for (var i = 0; i < 5; i++) numbers.labelOf(i)],
      [null, null, null, 'Slide 3', 'Slide 4'],
    );
    // Only one PDF is left: nothing to ask.
    expect(numbers.find(4), [4]);
    expect(numbers.find(1), [0]);
  });
}
