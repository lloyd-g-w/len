import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/paper.dart';
import 'package:len/ink/render/paper_painter.dart';
import 'package:len/ink/viewport.dart';

/// Renders an A4 page of [style] on white paper [width] pixels wide, the
/// way page thumbnails draw it.
Future<ByteData> miniature(PaperStyle style, double width) async {
  final page = Offset.zero & PageFormat.a4.sizeFor(PageOrientation.portrait);
  final scale = width / page.width;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(scale)
    ..clipRect(page);
  PaperRenderer.paintSheet(canvas, page, PaperColor.white, scale: scale, shadow: false);
  PaperRenderer.paintPattern(
    canvas,
    Paper(style),
    PaperColor.white,
    page,
    page: page,
    scale: scale,
    thumbnail: true,
  );
  final image = await recorder.endRecording().toImage(width.round(), (page.height * scale).round());
  final bytes = (await image.toByteData())!;
  image.dispose();
  return bytes;
}

/// How much darker than the paper the pattern makes the page on average
/// (luminance; the red margin line is left out).
double darkening(ByteData rgba) {
  final paper = PaperColor.white.paper.computeLuminance();
  var sum = 0.0, total = 0;
  for (var i = 0; i < rgba.lengthInBytes; i += 4) {
    total++;
    final c = Color.fromARGB(255, rgba.getUint8(i), rgba.getUint8(i + 1), rgba.getUint8(i + 2));
    if (c.r > c.g + 0.1) continue; // The margin line.
    sum += paper - c.computeLuminance();
  }
  return sum / total;
}

void main() {
  // R5-23: dots and fine lines must not drop out of page thumbnails.
  for (final style in [
    PaperStyle.dotted,
    PaperStyle.gridSmall,
    PaperStyle.music,
    PaperStyle.collegeRuled,
    PaperStyle.narrowRuled,
  ]) {
    test('a ${style.name} page still shows its pattern as a thumbnail', () async {
      for (final (width, least) in [(96.0, 0.04), (150.0, 0.02)]) {
        final dark = darkening(await miniature(style, width));
        expect(dark, greaterThan(least), reason: '${style.name} at $width px: $dark');
      }
    });
  }

  test('library previews keep dots the editor would hide at that zoom', () async {
    Future<double> preview({required bool miniature}) async {
      final page = Offset.zero & PageFormat.a4.sizeFor(PageOrientation.portrait);
      const size = Size(150, 100);
      final viewport = ViewportController(minScale: 1e-4, maxScale: 1e4)
        ..setSize(size)
        ..contentBounds = page
        ..fitWidth(padding: 0);
      final recorder = ui.PictureRecorder();
      PaperPainter(
        viewport: viewport,
        paper: const Paper(PaperStyle.dotted),
        page: page,
        miniature: miniature,
      ).paint(Canvas(recorder), size);
      final image = await recorder.endRecording().toImage(150, 100);
      final bytes = (await image.toByteData())!;
      image.dispose();
      return darkening(bytes);
    }

    expect(await preview(miniature: false), 0);
    expect(await preview(miniature: true), greaterThan(0.02));
  });

  test('blank stays blank', () async {
    expect(darkening(await miniature(PaperStyle.blank, 150)), 0);
  });
}
