import 'dart:async';
import 'dart:math';

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

void main() {
  // On the web the export runs on the page's only thread: a dense page's
  // ink took 2.6 s in one task (WebAssembly), the tab frozen meanwhile.
  test('writing a dense page lets the event loop turn while its ink is written', () async {
    const page = NotebookPage(
      id: 'p',
      notebookId: 'n',
      sortKey: 0,
      width: 794,
      height: 1123,
      paper: Paper(PaperStyle.blank),
    );
    final ink = denseInk(150);
    var turns = 0;
    var writing = true;
    void tick() {
      if (!writing) return;
      turns++;
      Timer(Duration.zero, tick);
    }

    Timer(Duration.zero, tick);
    final pdf = await PdfExporter.build([ExportPage(page, ink)]);
    writing = false;
    expect(pdf, isNotEmpty);
    // The ink alone takes hundreds of milliseconds: dozens of turns at one
    // per [PdfExporter.yieldEvery]; written in one go, a few at most.
    expect(turns, greaterThan(10));
  });
}
