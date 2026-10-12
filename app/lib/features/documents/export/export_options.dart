import '../../../domain/notebook_page.dart';
import '../../../domain/paper.dart';

/// The file format of an export.
enum ExportFormat {
  pdf('PDF', 'pdf', 'application/pdf'),
  png('PNG', 'png', 'image/png');

  const ExportFormat(this.label, this.extension, this.mime);

  final String label;
  final String extension;
  final String mime;
}

/// Which pages the export sheet offers to export.
enum ExportRange { current, all, custom }

/// Pixels per page unit of exported PNGs (a page unit is 1/96 in):
/// 288 dpi, sharp enough to print.
const double pngScale = 3;

/// Dots per inch of exported PNGs.
final int pngDpi = (pngScale * 96).round();

/// What to export: the format, which pages (zero-based indices into the
/// notebook, ascending) and what to draw under the ink.
class ExportOptions {
  const ExportOptions({
    required this.format,
    required this.pages,
    this.includeTemplates = true,
    this.includeBackgrounds = true,
  });

  final ExportFormat format;
  final List<int> pages;

  /// Lines, grid or dots and the paper colour; off = plain white paper.
  final bool includeTemplates;

  /// Imported PDF pages under the ink.
  final bool includeBackgrounds;

  /// The notebook pages to export, as they should be drawn.
  List<NotebookPage> resolve(List<NotebookPage> all) => [
    for (final i in pages)
      if (i >= 0 && i < all.length) exportedPage(all[i], includeTemplate: includeTemplates),
  ];

  /// "3 pages · PDF", "1 page · PNG · 288 dpi".
  String get summary {
    final count = '${pages.length} ${pages.length == 1 ? 'page' : 'pages'}';
    return switch (format) {
      ExportFormat.pdf => '$count · PDF',
      ExportFormat.png => '$count · PNG · $pngDpi dpi',
    };
  }
}

/// [page] as exported: without a template it is plain white paper.
NotebookPage exportedPage(NotebookPage page, {required bool includeTemplate}) =>
    includeTemplate ? page : page.copyWith(paper: Paper.blank, paperColor: PaperColor.white);

/// Parses a page range such as "1-3, 5" for a notebook of [count] pages
/// into ascending zero-based indices, or explains what is wrong.
({List<int>? pages, String? error}) parsePageRange(String text, int count) {
  final parts = text.split(RegExp(r'[,;]')).map((p) => p.trim()).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return (pages: null, error: 'Enter pages, e.g. 1-3, 5');
  final pages = <int>{};
  final single = RegExp(r'^(\d+)$');
  final span = RegExp(r'^(\d+)\s*[-–]\s*(\d+)$');
  for (final part in parts) {
    final int from, to;
    if (single.firstMatch(part) case final m?) {
      from = to = int.parse(m[1]!);
    } else if (span.firstMatch(part) case final m?) {
      from = int.parse(m[1]!);
      to = int.parse(m[2]!);
    } else {
      return (pages: null, error: '“$part” is not a page or range');
    }
    if (from < 1 || to < 1 || from > count || to > count) {
      return (pages: null, error: count == 1 ? 'Only page 1 exists' : 'Pages are 1–$count');
    }
    if (from > to) return (pages: null, error: '“$part” runs backwards');
    for (var n = from; n <= to; n++) {
      pages.add(n - 1);
    }
  }
  return (pages: pages.toList()..sort(), error: null);
}

/// Ascending zero-based [pages] as a compact one-based range: "1-3,5".
String formatPageRange(List<int> pages, {String separator = ','}) {
  final parts = <String>[];
  for (var i = 0; i < pages.length;) {
    var j = i;
    while (j + 1 < pages.length && pages[j + 1] == pages[j] + 1) {
      j++;
    }
    final a = pages[i] + 1, b = pages[j] + 1;
    parts.add(a == b ? '$a' : '$a-$b');
    i = j + 1;
  }
  return parts.join(separator);
}

/// File names for exporting [pages] of a notebook titled [title] with
/// [total] pages: one PDF ("Title.pdf" for the whole notebook, else
/// "Title p1-3,5.pdf") or one PNG per page ("Title p3.png").
List<String> exportFileNames(String title, ExportFormat format, List<int> pages, int total) {
  final base = safeFileName(title);
  final ext = format.extension;
  if (format == ExportFormat.png) return [for (final i in pages) '$base p${i + 1}.$ext'];
  final whole = pages.length == total;
  return [whole ? '$base.$ext' : '$base p${formatPageRange(pages)}.$ext'];
}

/// A file name from a notebook title.
String safeFileName(String title) {
  final cleaned = title.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ').trim();
  return cleaned.isEmpty ? 'Notebook' : cleaned;
}
