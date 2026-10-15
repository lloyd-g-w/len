import 'notebook_page.dart';

/// The PDF page numbers of a notebook's pages (UX_AUDIT R18-5): pages keep
/// their notebook numbers everywhere; a page showing a PDF page also has
/// that page's own number, shown quietly where pages are listed ("Slide 23",
/// "PDF p. 23") and accepted by Go to page ("s23", "slide 23").
class PdfPageNumbers {
  /// The numbers of [pages] (the notebook's, in order).
  PdfPageNumbers(this.pages) {
    final landscape = <String, int>{};
    final all = <String, int>{};
    for (final p in pages) {
      final pdf = p.pdf;
      if (pdf == null) continue;
      all[pdf.blob] = (all[pdf.blob] ?? 0) + 1;
      if (p.width > p.height) landscape[pdf.blob] = (landscape[pdf.blob] ?? 0) + 1;
    }
    _slides = {
      for (final e in all.entries)
        if ((landscape[e.key] ?? 0) * 2 > e.value) e.key,
    };
  }

  final List<NotebookPage> pages;

  /// PDFs most of whose pages are landscape: slide decks.
  late final Set<String> _slides;

  /// The one-based number of page [index] within its PDF, or null if it
  /// shows none.
  int? pdfNumberOf(int index) {
    final pdf = pages[index].pdf;
    return pdf == null ? null : pdf.pageIndex + 1;
  }

  /// Page [index]'s PDF page number as a label ("Slide 23" in a deck of
  /// landscape pages, else "PDF p. 23"), or null when it shows no PDF page
  /// or the number is its page number anyway (no noise for a plain import).
  String? labelOf(int index) {
    final number = pdfNumberOf(index);
    if (number == null || number == index + 1) return null;
    return _slides.contains(pages[index].pdf!.blob) ? 'Slide $number' : 'PDF p. $number';
  }

  /// Whether any page has a [labelOf] (Go to page then offers a keyboard
  /// for "s23").
  bool get hasLabels {
    for (var i = 0; i < pages.length; i++) {
      if (labelOf(i) != null) return true;
    }
    return false;
  }

  /// The pages showing page [number] (one-based) of a PDF: the first such
  /// page of each PDF, in notebook order. When the PDF of [current]'s page
  /// (a notes page: of the nearest PDF page before it, else after it) has
  /// [number], only that PDF's page is returned.
  List<int> find(int number, {int? current}) {
    final firstOf = <String, int>{};
    for (var i = 0; i < pages.length; i++) {
      final pdf = pages[i].pdf;
      if (pdf != null && pdf.pageIndex + 1 == number) firstOf.putIfAbsent(pdf.blob, () => i);
    }
    if (firstOf[_pdfNear(current)] case final i?) return [i];
    return firstOf.values.toList()..sort();
  }

  /// The PDF page [index] belongs to: its own, or the nearest PDF page's
  /// before it (the deck a notes page was added to), else after it.
  String? _pdfNear(int? index) {
    if (index == null || index < 0 || index >= pages.length) return null;
    for (var i = index; i >= 0; i--) {
      if (pages[i].pdf case final pdf?) return pdf.blob;
    }
    for (var i = index + 1; i < pages.length; i++) {
      if (pages[i].pdf case final pdf?) return pdf.blob;
    }
    return null;
  }

  static final _query = RegExp(r'^(?:s|slide|pdf(?:\s*p\.?)?)\s*(\d+)$', caseSensitive: false);

  /// The PDF page number [text] asks for ("s23", "slide 23", "pdf p. 23"),
  /// or null if it is not such a query.
  static int? parse(String text) {
    final match = _query.firstMatch(text.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}
