import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/documents/export/pdf_export.dart';

/// [count] long jittery strokes, like a dense handwritten page.
List<Stroke> denseInk(int count) {
  final rnd = Random(7);
  return [
    for (var k = 0; k < count; k++)
      () {
        var x = 60 + rnd.nextDouble() * 640, y = 60 + rnd.nextDouble() * 990;
        return Stroke(
          id: 's$k',
          surfaceId: 'p',
          tool: InkTool.ballpoint,
          color: 0xFF000000,
          width: 2,
          points: [
            for (var i = 0; i < 150; i++)
              StrokePoint(x += rnd.nextDouble() * 7 - 3, y += rnd.nextDouble() * 6 - 3, 0.5),
          ],
          createdAt: k,
        );
      }(),
  ];
}

const _page = NotebookPage(
  id: 'p',
  notebookId: 'n',
  sortKey: 0,
  width: 794,
  height: 1123,
  paper: Paper(PaperStyle.blank),
);

/// The decompressed content of each Flate stream in [pdf].
List<String> flateStreams(Uint8List pdf) {
  final text = latin1.decode(pdf);
  return [
    for (final m in RegExp(r'/FlateDecode[^>]*>>\s*stream\n').allMatches(text))
      () {
        final end = text.indexOf('\nendstream', m.end);
        return latin1.decode(zlib.decode(pdf.sublist(m.end, end)));
      }(),
  ];
}

void main() {
  // On the web the export runs on the page's only thread: a dense page's
  // ink took 2.6 s in one task (WebAssembly), the tab frozen meanwhile.
  test('writing a dense page lets the event loop turn while its ink is written', () async {
    final ink = denseInk(150);
    var turns = 0;
    var writing = true;
    void tick() {
      if (!writing) return;
      turns++;
      Timer(Duration.zero, tick);
    }

    Timer(Duration.zero, tick);
    final pdf = await PdfExporter.build([ExportPage(_page, ink)]);
    writing = false;
    expect(pdf, isNotEmpty);
    // The ink alone takes hundreds of milliseconds: dozens of turns at one
    // per [PdfExporter.yieldEvery]; written in one go, a few at most.
    expect(turns, greaterThan(10));
  });

  // Saving compresses one stream at a time, in a browser in pure Dart on
  // the page's thread: a dense page's 4 MB of ink in one stream held the
  // tab 2.3 s (WebAssembly). Its ink goes into streams of a bounded size.
  test('a dense page\'s ink is written in several content streams of bounded size', () async {
    final pdf = await PdfExporter.build([ExportPage(_page, denseInk(150))]);
    final ink = flateStreams(pdf).where((s) => RegExp(r' c\s').hasMatch(s)).toList();
    expect(ink.length, greaterThan(3));
    // One stroke may run past the bound.
    for (final s in ink) {
      expect(s.length, lessThan(160 * 1024));
    }
    // Every stroke whole (q … Q) within one stream.
    for (final s in ink) {
      final saves = RegExp(r'(^|\s)q\s').allMatches(s).length;
      expect(saves, greaterThan(0));
      expect(RegExp(r'(^|\s)Q\s').allMatches(s).length, saves);
    }
  });
}
