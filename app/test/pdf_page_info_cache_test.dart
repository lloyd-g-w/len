import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/pdf/pdf_page_info.dart';
import 'package:len/features/editor/pdf/pdf_page_info_cache.dart';

/// Answers each glyph read when the test says so, with what the PDF
/// holds at that moment (null while it is not on this device).
class _Source implements PdfInfoSource {
  bool present = false;
  final List<Completer<void>> reads = [];

  @override
  Future<PdfGlyphs?> glyphs(String blob, int page) async {
    final here = present; // As read when the read started.
    final go = Completer<void>();
    reads.add(go);
    await go.future;
    return here ? PdfGlyphs('A', [const Rect.fromLTWH(0, 0, .1, .1)]) : null;
  }

  @override
  Future<List<PdfLinkArea>> links(String blob, int page) async => const [];

  @override
  Future<List<PdfOutlineItem>> outline(String blob) async => const [];
}

void main() {
  // A sync brings a PDF while one of its pages is being read (finding
  // nothing): the retry it asks for must not be undone by that read.
  test('a read started before a retry does not keep the page without text', () async {
    final source = _Source();
    final cache = PdfPageInfoCache(source);
    addTearDown(cache.dispose);
    expect(cache.glyphs('b', 0), isNull); // Starts a read: not here yet.
    await pumpEventQueue();
    expect(source.reads, hasLength(1));

    source.present = true; // Synced.
    cache.retry();
    cache.glyphs('b', 0); // Painted again after the retry.
    source.reads.first.complete(); // The old read ends: it found nothing.
    await pumpEventQueue();
    for (final read in source.reads.skip(1)) {
      read.complete();
    }
    await pumpEventQueue();

    expect(cache.glyphs('b', 0)?.text, 'A');
  });
}
