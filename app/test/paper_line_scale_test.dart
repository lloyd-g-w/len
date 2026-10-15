import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/paper_pattern.dart';
import 'package:len/features/documents/export/pdf_template.dart';
import 'package:len/features/documents/export/pdf_text.dart';
import 'package:len/features/editor/document/page_painting.dart';
import 'package:len/ink/render/paper_painter.dart';
import 'package:pdf/pdf.dart';

/// Ruled paper in opaque black, so a pixel's darkness is the line's
/// coverage of it.
const _black = PaperLook(patternColor: 0xFF000000);

/// The ink of the rows [top] to [bottom] of [rgba] ([width] pixels wide;
/// black on white) per column: a horizontal line's width in pixels.
double _inkPerColumn(ByteData rgba, int width, int top, int bottom) {
  var sum = 0.0;
  for (var y = top; y < bottom; y++) {
    for (var x = 0; x < width; x++) {
      sum += 1 - rgba.getUint8(4 * (y * width + x)) / 255;
    }
  }
  return sum / width;
}

/// The darkest pixel's darkness in [rgba].
double _peak(ByteData rgba) {
  var peak = 0.0;
  for (var i = 0; i < rgba.lengthInBytes; i += 4) {
    peak = math.max(peak, 1 - rgba.getUint8(i) / 255);
  }
  return peak;
}

/// Renders one pitch of ruled canvas paper around the line at [pitch], a
/// few units wide, at [zoom] device pixels per world unit, as the editor's
/// painters do; returns the pixels and the image's width.
Future<(ByteData, int)> _strip(Paper paper, double zoom) async {
  final pitch = paper.pitch;
  final area = Rect.fromLTWH(0, pitch / 2, 8, pitch);
  final w = (area.width * zoom).round(), h = (area.height * zoom).round();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    )
    ..scale(zoom)
    ..translate(-area.left, -area.top)
    ..clipRect(area);
  PaperRenderer.paintPattern(canvas, paper, PaperColor.white, area, scale: zoom);
  final image = await recorder.endRecording().toImage(w, h);
  final bytes = (await image.toByteData())!;
  image.dispose();
  return (bytes, w);
}

/// Records the line widths set in a PDF.
class _Widths extends PdfGraphics {
  _Widths(super.page, super.buf);

  final List<double> widths = [];

  @override
  void setLineWidth(double width) {
    widths.add(width);
    super.setLineWidth(width);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paper = Paper(PaperStyle.collegeRuled, look: _black);
  final world = PaperRenderer.lineWidth(PatternWeight.normal);

  test('lines scale with the page: their device-pixel width is linear in the zoom', () async {
    for (final zoom in [1.0, 2.0, 4.0, 8.0]) {
      final (rgba, w) = await _strip(paper, zoom);
      final ink = _inkPerColumn(rgba, w, 0, rgba.lengthInBytes ~/ (4 * w));
      expect(ink, closeTo(world * zoom, 0.08 * world * zoom), reason: 'at ${zoom * 100} %');
      // Wide enough to cover a pixel: drawn solid, not faded.
      if (world * zoom >= 1.5) expect(_peak(rgba), greaterThan(0.95));
    }
    // The look's line weight scales them too.
    const heavy = Paper(
      PaperStyle.collegeRuled,
      look: PaperLook(patternColor: 0xFF000000, lineWeight: 2),
    );
    final (rgba, w) = await _strip(heavy, 4);
    expect(
      _inkPerColumn(rgba, w, 0, rgba.lengthInBytes ~/ (4 * w)),
      closeTo(2 * world * 4, 0.08 * 2 * world * 4),
    );
  });

  test('far out, lines fade at half a pixel instead of thinning, keeping their ink', () async {
    // 0.3 × 2/3: a fifth of a pixel wide, still above the density threshold.
    const zoom = 0.3;
    final (rgba, w) = await _strip(paper, zoom);
    final ink = _inkPerColumn(rgba, w, 0, rgba.lengthInBytes ~/ (4 * w));
    expect(ink, closeTo(world * zoom, 0.03));
    expect(_peak(rgba), lessThan(0.5));
  });

  test('the density threshold still hides lines too close to read', () async {
    final zoom = PaperRenderer.minScreenSpacing / paper.pitch * 0.9;
    final (rgba, _) = await _strip(paper, zoom);
    expect(_peak(rgba), 0);
  });

  test('PNG export draws the lines at their world width (288 dpi)', () async {
    const scale = 3.0;
    final page = NotebookPage(
      id: 'p',
      notebookId: 'n',
      sortKey: 0,
      width: 794,
      height: 1123,
      paper: paper,
    );
    final rect = Offset.zero & page.size;
    final line = PaperPattern.of(
      paper,
      rect,
      page: rect,
    ).lines.firstWhere((l) => l.weight == PatternWeight.normal);
    final image = await renderPageImage(page, strokes: const [], scale: scale);
    final rgba = (await image.toByteData())!;
    // A column band in the middle of the page, within half a pitch of the line.
    final half = (paper.pitch / 2 * scale).floor();
    final cy = (line.a.dy * scale).round();
    final x0 = image.width ~/ 2, band = 40;
    final cell = ByteData(4 * band * 2 * half);
    var o = 0;
    for (var y = cy - half; y < cy + half; y++) {
      for (var x = x0; x < x0 + band; x++) {
        cell.setUint32(o, rgba.getUint32(4 * (y * image.width + x)));
        o += 4;
      }
    }
    image.dispose();
    // 0.5 pt at 4 pixels per point.
    expect(_inkPerColumn(cell, band, 0, 2 * half), closeTo(world * scale, 0.08 * world * scale));
    expect(world * scale, closeTo(2, 1e-9));
  });

  test('PDF export writes the lines at the same world widths', () async {
    final doc = PdfDocument();
    final g = _Widths(PdfPage(doc), PdfStream());
    await PdfTemplateWriter(PdfTextWriter(doc)).draw(
      g,
      const PaperPattern(
        lines: <PatternLine>[
          (a: Offset(0, 10), b: Offset(10, 10), weight: PatternWeight.fine),
          (a: Offset(0, 20), b: Offset(10, 20), weight: PatternWeight.normal),
          (a: Offset(0, 30), b: Offset(10, 30), weight: PatternWeight.heavy),
          (a: Offset(0, 40), b: Offset(10, 40), weight: PatternWeight.margin),
        ],
      ),
      PaperColor.white,
      look: const PaperLook(lineWeight: 1.5),
      margin: const Color(0xFFFF0000),
      map: (o) => o * 0.75,
      k: 0.75,
    );
    // 0.3, 0.5, 0.9 and 0.9 pt × the weight.
    expect(g.widths, [
      for (final w in [0.3, 0.5, 0.9, 0.9]) closeTo(w * 1.5, 1e-9),
    ]);
  });
}
