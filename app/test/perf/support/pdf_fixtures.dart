import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' as pw;

/// Realistic PDFs for the PDF viewing benchmarks, generated once and kept
/// in the system temp directory (`len_pdf_perf_fixtures_v1/`): building
/// the scans takes a while in the debug VM.
///
/// - [textbook]: 300 A4 pages of body text in embedded TrueType fonts
///   (Lora, Inter headings; ~4,000 characters a page), a figure every
///   fifth page: a textbook.
/// - [scanned]: 50 A4 pages, each one 2480 × 3508 JPEG (300 dpi, colour,
///   paper noise and lines of "ink"): a scanned handout.
/// - [vector]: 4 A3 landscape pages of maps: ~12,000 coloured polylines,
///   ~3,000 filled polygons and ~600 labels each.
abstract final class PdfFixtures {
  static final Directory dir = Directory('${Directory.systemTemp.path}/len_pdf_perf_fixtures_v1');

  static Future<File> textbook() => _cached('textbook_300.pdf', _textbook);
  static Future<File> scanned() => _cached('scanned_50.pdf', _scanned);
  static Future<File> vector() => _cached('vector_maps_4.pdf', _vector);

  static Future<File> _cached(String name, Future<Uint8List> Function() make) async {
    final file = File('${dir.path}/$name');
    if (file.existsSync() && file.lengthSync() > 0) return file;
    dir.createSync(recursive: true);
    final tmp = File('${file.path}.tmp')..writeAsBytesSync(await make());
    return tmp.renameSync(file.path);
  }

  static pw.PdfTtfFont _font(pw.PdfDocument doc, String asset) =>
      pw.PdfTtfFont(doc, ByteData.sublistView(File('assets/fonts/$asset').readAsBytesSync()));

  static const _words = [
    'the',
    'of',
    'energy',
    'function',
    'system',
    'which',
    'theorem',
    'given',
    'field',
    'and',
    'a',
    'is',
    'equation',
    'where',
    'we',
    'define',
    'boundary',
    'value',
    'integral',
    'to',
    'by',
    'linear',
    'operator',
    'space',
    'that',
    'in',
    'condition',
    'for',
    'each',
    'point',
    'proof',
    'follows',
    'from',
    'lemma',
    'hence',
    'constant',
    'derivative',
    'with',
    'respect',
  ];

  static Future<Uint8List> _textbook() async {
    final doc = pw.PdfDocument();
    final body = _font(doc, 'Lora-Regular.ttf');
    final bold = _font(doc, 'Inter-Bold.ttf');
    final italic = _font(doc, 'Lora-Italic.ttf');
    final r = math.Random(7);
    for (var p = 0; p < 300; p++) {
      final page = pw.PdfPage(doc, pageFormat: pw.PdfPageFormat.a4);
      final g = page.getGraphics()..setFillColor(pw.PdfColors.black);
      var y = 790.0;
      if (p % 10 == 0) {
        g.drawString(bold, 20, 'Chapter ${p ~/ 10 + 1}: Fields and boundaries', 60, y);
        y -= 36;
      }
      final figure = p % 5 == 2;
      while (y > 60) {
        if (figure && y < 500 && y > 300) {
          _figure(g, r, 60, y - 190, 475, 180);
          y -= 210;
          continue;
        }
        final line = StringBuffer();
        while (line.length < 88) {
          line
            ..write(_words[r.nextInt(_words.length)])
            ..write(' ');
        }
        g
          ..setFillColor(pw.PdfColors.black)
          ..drawString(r.nextInt(12) == 0 ? italic : body, 10.5, line.toString(), 60, y);
        y -= 15;
      }
      g.drawString(body, 9, '${p + 1}', 290, 30);
    }
    return doc.save();
  }

  static void _figure(pw.PdfGraphics g, math.Random r, double x, double y, double w, double h) {
    g
      ..setStrokeColor(pw.PdfColors.grey700)
      ..setLineWidth(0.6)
      ..drawRect(x, y, w, h)
      ..strokePath();
    for (var s = 0; s < 3; s++) {
      g
        ..setStrokeColor([pw.PdfColors.blue700, pw.PdfColors.red700, pw.PdfColors.green700][s])
        ..moveTo(x, y + h / 2);
      for (var i = 1; i <= 120; i++) {
        g.lineTo(x + w * i / 120, y + h / 2 + math.sin(i / 9 + s) * h * 0.35 + r.nextDouble() * 4);
      }
      g.strokePath();
    }
  }

  /// A 300-dpi A4 colour scan: off-white paper with noise and dark text
  /// lines (variant [v] moves them).
  static Uint8List _scanJpeg(int v) {
    const w = 2480, h = 3508;
    final r = math.Random(v);
    final bytes = Uint8List(w * h * 3);
    for (var y = 0; y < h; y++) {
      final inLine = y > 300 && y < 3300 && (y ~/ 60 + v) % 2 == 0 && (y % 60) < 34;
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 3;
        final n = r.nextInt(24);
        final ink = inLine && x > 250 && x < 2230 && ((x ~/ 23 + y ~/ 60 * 7) % 9 != 0);
        final base = ink ? 40 + n : 232 + (n >> 1);
        bytes[i] = base;
        bytes[i + 1] = base - 2;
        bytes[i + 2] = base - 8;
      }
    }
    final image = img.Image.fromBytes(width: w, height: h, bytes: bytes.buffer, numChannels: 3);
    return img.encodeJpg(image, quality: 80);
  }

  static Future<Uint8List> _scanned() async {
    final doc = pw.PdfDocument();
    final jpegs = [for (var v = 0; v < 3; v++) _scanJpeg(v)];
    for (var p = 0; p < 50; p++) {
      final page = pw.PdfPage(doc, pageFormat: pw.PdfPageFormat.a4);
      // A separate image object per page, as a scanner writes them.
      final image = pw.PdfImage.jpeg(doc, image: jpegs[p % jpegs.length]);
      page.getGraphics().drawImage(image, 0, 0, page.pageFormat.width, page.pageFormat.height);
    }
    return doc.save();
  }

  static Future<Uint8List> _vector() async {
    final doc = pw.PdfDocument();
    final label = _font(doc, 'Inter-Regular.ttf');
    final format = pw.PdfPageFormat.a3.landscape;
    for (var p = 0; p < 4; p++) {
      final r = math.Random(100 + p);
      final page = pw.PdfPage(doc, pageFormat: format);
      final g = page.getGraphics();
      final W = format.width, H = format.height;
      for (var i = 0; i < 3000; i++) {
        final cx = r.nextDouble() * W, cy = r.nextDouble() * H, s = 4 + r.nextDouble() * 30;
        g
          ..setFillColor(pw.PdfColor(0.6 + r.nextDouble() * 0.4, 0.8 + r.nextDouble() * 0.2, 0.6))
          ..moveTo(cx, cy);
        for (var k = 1; k < 8; k++) {
          final a = k / 8 * 2 * math.pi;
          g.lineTo(cx + math.cos(a) * s * (0.6 + r.nextDouble()), cy + math.sin(a) * s);
        }
        g.fillPath();
      }
      for (var i = 0; i < 12000; i++) {
        var x = r.nextDouble() * W, y = r.nextDouble() * H;
        g
          ..setStrokeColor(pw.PdfColor(r.nextDouble() * 0.5, r.nextDouble() * 0.5, r.nextDouble()))
          ..setLineWidth(0.2 + r.nextDouble() * 1.5)
          ..moveTo(x, y);
        for (var k = 0; k < 10; k++) {
          x += (r.nextDouble() - 0.5) * 20;
          y += (r.nextDouble() - 0.5) * 20;
          g.lineTo(x, y);
        }
        g.strokePath();
      }
      g.setFillColor(pw.PdfColors.black);
      for (var i = 0; i < 600; i++) {
        g.drawString(
          label,
          4 + r.nextDouble() * 4,
          'Station ${r.nextInt(999)}',
          r.nextDouble() * W,
          r.nextDouble() * H,
        );
      }
    }
    return doc.save();
  }
}
