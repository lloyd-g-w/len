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

/// Dotted paper in opaque black, so a pixel's darkness is the dot's
/// coverage of it.
const _black = PaperLook(patternColor: 0xFF000000);

/// The dots' total area in [rgba] (black on white), in pixels².
double _inkArea(ByteData rgba) {
  var sum = 0.0;
  for (var i = 0; i < rgba.lengthInBytes; i += 4) {
    sum += 1 - rgba.getUint8(i) / 255;
  }
  return sum;
}

/// The diameter of a round dot covering [area] pixels².
double _diameter(double area) => 2 * math.sqrt(area / math.pi);

/// The darkest pixel's darkness in [rgba].
double _peak(ByteData rgba) {
  var peak = 0.0;
  for (var i = 0; i < rgba.lengthInBytes; i += 4) {
    peak = math.max(peak, 1 - rgba.getUint8(i) / 255);
  }
  return peak;
}

/// Renders the one pitch of dotted canvas paper around the dot at
/// ([pitch], [pitch]) at [zoom] device pixels per world unit, as the
/// editor's painters do.
Future<ByteData> _cell(Paper paper, double zoom) async {
  final pitch = paper.pitch;
  final area = Rect.fromCenter(center: Offset(pitch, pitch), width: pitch, height: pitch);
  final px = (pitch * zoom).round();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      Rect.fromLTWH(0, 0, px.toDouble(), px.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    )
    ..scale(zoom)
    ..translate(-area.left, -area.top)
    ..clipRect(area);
  PaperRenderer.paintPattern(canvas, paper, PaperColor.white, area, scale: zoom);
  final image = await recorder.endRecording().toImage(px, px);
  final bytes = (await image.toByteData())!;
  image.dispose();
  return bytes;
}

/// Records the radii of the ellipses drawn into a PDF.
class _Ellipses extends PdfGraphics {
  _Ellipses(super.page, super.buf);

  final List<double> radii = [];

  @override
  void drawEllipse(double x, double y, double r1, double r2, {bool clockwise = true}) {
    radii.add(r1);
    super.drawEllipse(x, y, r1, r2, clockwise: clockwise);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paper = Paper(PaperStyle.dotted, look: _black);
  const world = 2 * PaperRenderer.dotRadius;

  test('dots scale with the page: their device-pixel diameter is linear in the zoom', () async {
    for (final zoom in [0.5, 1.0, 2.0, 4.0]) {
      final d = _diameter(_inkArea(await _cell(paper, zoom)));
      expect(d, closeTo(world * zoom, 0.08 * world * zoom), reason: 'at ${zoom * 100} %');
    }
    // The look's dot size scales them too.
    const big = Paper(PaperStyle.dotted, look: PaperLook(patternColor: 0xFF000000, dotSize: 2));
    expect(_diameter(_inkArea(await _cell(big, 2))), closeTo(2 * world * 2, 0.4));
  });

  test('far out, dots stay half a pixel and fade by the square root of the area lost', () async {
    // Sparse and small, so they still show at 20 %: 0.14 px in radius.
    const sparse = Paper(
      PaperStyle.dotted,
      look: PaperLook(patternColor: 0xFF000000, spacing: 20, dotSize: 0.5),
    );
    const zoom = 0.2;
    final cell = await _cell(sparse, zoom);
    final r = PaperRenderer.dotRadius * 0.5 * zoom;
    const min = PaperRenderer.minDotRadius;
    // Opacity r / min = √(r² / min²): more ink than the dot's own area
    // (contrast far out), as much as lines keep by the same rule.
    expect(_inkArea(cell), closeTo(math.pi * min * min * (r / min), 0.02));
    expect(_inkArea(cell), greaterThan(2 * math.pi * r * r));
    expect(_peak(cell), lessThan(0.3));
  });

  test('PNG export draws the dots at their world size (288 dpi)', () async {
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
    final dot = PaperPattern.of(paper, rect, page: rect).dots.first;
    final image = await renderPageImage(page, strokes: const [], scale: scale);
    final rgba = (await image.toByteData())!;
    // The pixels within half a pitch of the first dot.
    final half = (paper.pitch / 2 * scale).floor();
    final cx = (dot.dx * scale).round(), cy = (dot.dy * scale).round();
    final cell = ByteData(4 * (2 * half) * (2 * half));
    var o = 0;
    for (var y = cy - half; y < cy + half; y++) {
      for (var x = cx - half; x < cx + half; x++) {
        cell.setUint32(o, rgba.getUint32(4 * (y * image.width + x)));
        o += 4;
      }
    }
    image.dispose();
    expect(_diameter(_inkArea(cell)), closeTo(world * scale, 0.08 * world * scale));
  });

  test('PDF export writes the dots at the same world size', () async {
    final doc = PdfDocument();
    final g = _Ellipses(PdfPage(doc), PdfStream());
    await PdfTemplateWriter(PdfTextWriter(doc)).draw(
      g,
      const PaperPattern(dots: [Offset(32, 32)]),
      PaperColor.white,
      look: const PaperLook(dotSize: 1.5),
      margin: const Color(0xFFFF0000),
      map: (o) => o * 0.75,
      k: 0.75,
    );
    expect(g.radii.single, closeTo(PaperRenderer.dotRadius * 1.5 * 0.75, 1e-9));
  });
}
