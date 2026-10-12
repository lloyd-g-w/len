/// Reads the link annotations of a source PDF page.
library;

import 'dart:ui' show Rect;

import '../../../../domain/pdf_page_space.dart';
import 'cos.dart';
import 'pdf_source_reader.dart';

/// The links of page [pageIndex] of [source] whose visible box is [crop]
/// (`[x0 y0 x1 y1]` in page space): web links (`/URI` actions) and links
/// to pages of the same file (`/GoTo` actions and `/Dest`, explicit or
/// named), with their areas normalised to the page as shown (`/Rotate`
/// applied). Other actions (launching files, scripts, other files) are
/// left out, as are links whose target cannot be found.
List<PdfLinkArea> readSourceLinks(PdfSourceReader source, int pageIndex, List<double> crop) {
  final page = source.pages[pageIndex];
  final annots = source.resolve(page.dict['Annots']);
  if (annots is! CosArray) return const [];
  final pages = {
    for (final (i, p) in source.pages.indexed)
      if (p.ref != null) p.ref!.number: i,
  };
  final names = _NamedDestinations(source);
  final result = <PdfLinkArea>[];
  for (final item in annots.items) {
    final a = source.resolve(item);
    if (a is! CosDict || source.resolve(a['Subtype']).asName != 'Link') continue;
    final flags = source.resolve(a['F']).asInt ?? 0;
    if (flags & 2 != 0 || flags & 32 != 0) continue; // Hidden, NoView
    final r = source.rectangle(a['Rect']);
    if (r == null) continue;
    Uri? url;
    int? target;
    final action = source.resolve(a['A']);
    if (action is CosDict) {
      switch (source.resolve(action['S']).asName) {
        case 'URI':
          final uri = source.resolve(action['URI']);
          if (uri is CosString) url = Uri.tryParse(uri.text.trim());
        case 'GoTo':
          target = _pageOf(source, action['D'], pages, names);
      }
    } else {
      target = _pageOf(source, a['Dest'], pages, names);
    }
    if (url == null && target == null) continue;
    final area = _shown(r, crop, page.rotate ~/ 90);
    if (area == null) continue;
    result.add(PdfLinkArea([area], page: target, url: url));
  }
  return result;
}

/// [r] normalised to the page shown with [crop] turned by [turns]; null if
/// it lies outside.
Rect? _shown(List<double> r, List<double> crop, int turns) {
  final w = crop[2] - crop[0], h = crop[3] - crop[1];
  final shown = pdfRectToDisplay(
    r[0] - crop[0],
    r[1] - crop[1],
    r[2] - crop[0],
    r[3] - crop[1],
    width: w,
    height: h,
    quarterTurns: turns,
  ).intersect(const Rect.fromLTRB(0, 0, 1, 1));
  return shown.width > 0 && shown.height > 0 ? shown : null;
}

/// The page index a destination points at: an explicit `[page /XYZ …]`
/// array (the page as a reference, or as a number), a named destination,
/// or a dictionary with `/D`.
int? _pageOf(
  PdfSourceReader source,
  CosObject? dest,
  Map<int, int> pages,
  _NamedDestinations names, [
  int depth = 0,
]) {
  if (depth > 8) return null;
  final d = dest is CosRef ? dest : source.resolve(dest);
  switch (d) {
    case CosRef(:final number):
      // A reference to a page, or to an array / dictionary holding one.
      if (pages[number] case final page?) return page;
      return _pageOf(source, source.resolve(d), pages, names, depth + 1);
    case CosArray(:final items) when items.isNotEmpty:
      final first = items.first;
      if (first is CosRef) return pages[first.number];
      final n = source.resolve(first).asInt;
      return n != null && n >= 0 && n < source.pageCount ? n : null;
    case CosDict():
      return _pageOf(source, d['D'], pages, names, depth + 1);
    case CosName(:final name):
      return _pageOf(source, names.lookup(name), pages, names, depth + 1);
    case CosString(:final text):
      return _pageOf(source, names.lookup(text), pages, names, depth + 1);
    default:
      return null;
  }
}

/// The named destinations of a file: the catalog's `/Dests` dictionary
/// (PDF 1.1) and its `/Names /Dests` name tree.
class _NamedDestinations {
  _NamedDestinations(this.source);

  final PdfSourceReader source;
  Map<String, CosObject>? _all;

  CosObject? lookup(String name) => (_all ??= _read())[name];

  Map<String, CosObject> _read() {
    final all = <String, CosObject>{};
    final root = source.resolve(source.trailer['Root']);
    if (root is! CosDict) return all;
    final dests = source.resolve(root['Dests']);
    if (dests is CosDict) {
      for (final e in dests.entries.entries) {
        all[e.key] = e.value;
      }
    }
    final names = source.resolve(root['Names']);
    if (names is CosDict) _walk(names['Dests'], all, 0, <int>{});
    return all;
  }

  void _walk(CosObject? node, Map<String, CosObject> into, int depth, Set<int> seen) {
    if (depth > 32 || (node is CosRef && !seen.add(node.number))) return;
    final d = source.resolve(node);
    if (d is! CosDict) return;
    final pairs = source.resolve(d['Names']);
    if (pairs is CosArray) {
      for (var i = 0; i + 1 < pairs.items.length; i += 2) {
        final key = source.resolve(pairs.items[i]);
        if (key is CosString) into.putIfAbsent(key.text, () => pairs.items[i + 1]);
      }
    }
    final kids = source.resolve(d['Kids']);
    if (kids is CosArray) {
      for (final kid in kids.items) {
        _walk(kid, into, depth + 1, seen);
      }
    }
  }
}
