import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/documents/export/vector/cos.dart';
import 'package:len/features/documents/export/vector/imported_pdf_page.dart';
import 'package:len/features/documents/export/vector/pdf_filters.dart';
import 'package:len/features/documents/export/vector/pdf_lexer.dart';
import 'package:len/features/documents/export/vector/pdf_page_importer.dart';
import 'package:len/features/documents/export/vector/pdf_source_reader.dart';
import 'package:pdf/pdf.dart' as pw;
// ignore: implementation_imports
import 'package:pdf/src/priv.dart' show Ascii85Encoder;
import 'package:pdfrx/pdfrx.dart' as rx;

import 'support/pdf_fixtures.dart';

Uint8List b(String s) => Uint8List.fromList(latin1.encode(s));

CosObject parse(String s) => PdfParser(b(s)).parseObject();

const catalog = '<< /Type /Catalog /Pages 2 0 R >>';

/// A one-page file with a classic xref table: a red 100×50 box at the origin.
Uint8List simpleFile({
  String pageExtra = '',
  String content = '1 0 0 rg 0 0 100 50 re f',
  String mediaBox = '[0 0 200 100]',
}) {
  final pdf = RawPdf()
    ..obj(1, catalog)
    ..obj(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>')
    ..obj(3, '<< /Type /Page /Parent 2 0 R /MediaBox $mediaBox /Contents 4 0 R $pageExtra >>')
    ..stream(4, '<< /Length ${content.length} >>', latin1.encode(content));
  pdf.xrefTable('<< /Size 5 /Root 1 0 R >>');
  return pdf.finish();
}

String contentOf(PdfSourceReader r, int page) {
  final s = r.resolve(r.pages[page].dict['Contents']) as CosStream;
  return latin1.decode(decodeStreamData(s, r.resolve));
}

final String? pdfium = [
  '.dart_tool/hooks_runner/shared/pdfium_dart/build/chromium_7811/linux-x64/libpdfium.so',
  'build/native_assets/linux/libpdfium.so',
].map((p) => File(p).absolute.path).where((p) => File(p).existsSync()).firstOrNull;

void main() {
  group('lexer', () {
    test('literal strings: escapes, octal, balanced parens, continuations', () {
      final s = parse('(a\\(b\\)c\\\\ (nested) \\101\\60x \\n\\t\\q\\\ncont\r\nend)') as CosString;
      expect(s.text, 'a(b)c\\ (nested) A0x \n\tqcont\nend');
      expect(s.hex, isFalse);
    });

    test('hex strings, names, numbers, keywords', () {
      final h = parse('<48 65 6C6C 6F7>') as CosString;
      expect(h.text, 'Hellop');
      expect(h.hex, isTrue);
      expect((parse('/A#20B#2') as CosName).name, 'A B#2');
      expect(parse('-.5').asNum, -0.5);
      expect(parse('+12').asNum, 12);
      expect(parse('3.').asNum, 3.0);
      expect(parse('42').asNum, isA<int>());
      expect(() => parse('0x1F'), throwsA(isA<PdfReadException>()));
      expect(parse('true'), isA<CosBool>());
      expect(parse('null'), CosNull.instance);
    });

    test('arrays, dicts, refs and comments', () {
      final a =
          parse('[1 0 R 2 % comment ] here\n /N true false null 3.5 (s) [ ] 7 8]') as CosArray;
      expect(a.items.length, 11);
      expect(a.items[0], const CosRef(1, 0));
      expect(a.items[1].asInt, 2);
      expect(a.items[2], const CosName('N'));
      expect(a.items.sublist(9).map((e) => e.asInt), [7, 8]);
      final d = parse('<</A<</B[1 2]>>/C 5 0 R/D/E/F>>') as CosDict;
      expect((d['A'] as CosDict)['B'], isA<CosArray>());
      expect(d['C'], const CosRef(5, 0));
      expect(d['D'].asName, 'E');
      expect(d.entries.containsKey('F'), isFalse);
    });

    test('streams: wrong /Length falls back to endstream, indirect /Length', () {
      final p = PdfParser(b('7 0 obj << /Length 999 >> stream\r\nabc\r\nendstream endobj'));
      final o = p.parseIndirectObject();
      expect(o.number, 7);
      expect(latin1.decode((o.object as CosStream).raw), 'abc');
      final q = PdfParser(
        b('8 0 obj << /Length 9 0 R >>\nstream\nab endstream\nendstream\nendobj'),
        resolveLength: (r) => r.number == 9 ? 12 : null,
      );
      expect(latin1.decode((q.parseIndirectObject().object as CosStream).raw), 'ab endstream');
    });
  });

  group('filters', () {
    test('ASCII85 and ASCIIHex', () {
      final data = Uint8List.fromList(
        List.generate(203, (i) => (i * 37 + (i ~/ 7)) % 256)..addAll([0, 0, 0, 0]),
      );
      final a85 = Ascii85Encoder().convert(data);
      expect(decodeAscii85(Uint8List.fromList(a85)), data);
      expect(decodeAscii85(b('9jqo^z~>')), [77, 97, 110, 32, 0, 0, 0, 0]);
      expect(latin1.decode(decodeAsciiHex(b('48 65\n6c6C 6f7>'))), 'Hellop');
    });

    test('PNG predictors: Sub, Up, Average, Paeth', () {
      final parms = parse('<< /Predictor 15 /Columns 2 >>') as CosDict;
      for (final row2 in [
        [2, 5, 5],
        [3, 10, 8],
        [4, 5, 5],
      ]) {
        final out = applyPredictor(Uint8List.fromList([1, 10, 10, ...row2]), parms, (o) => o);
        expect(out, [10, 20, 15, 25]);
      }
    });
  });

  group('reader', () {
    test('classic xref, inheritance of Resources/MediaBox/CropBox/Rotate, Kids cycles', () {
      final pdf = RawPdf()
        ..obj(1, catalog)
        ..obj(
          2,
          '<< /Type /Pages /Kids [5 0 R 3 0 R 2 0 R] /Count 2 /MediaBox [0 0 300 400] '
          '/Resources << /Font << /F1 6 0 R >> >> /Rotate -90 >>',
        )
        ..obj(5, '<< /Type /Pages /Parent 2 0 R /Kids [3 0 R 7 0 R] /CropBox [400 10 50 300] >>')
        ..obj(3, '<< /Type /Page /Parent 5 0 R /Rotate 180 >>')
        ..obj(7, '<< /Type /Page /Parent 5 0 R /MediaBox [0 0 10 20] /Resources << >> >>')
        ..obj(6, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
      pdf.xrefTable('<< /Size 8 /Root 1 0 R >>');
      final r = PdfSourceReader.parse(pdf.finish());
      expect(r.pageCount, 2);
      expect(r.recoveredByScan, isFalse);
      final p0 = r.pages[0], p1 = r.pages[1];
      expect(p0.rotate, 180);
      expect(p0.mediaBox, [0, 0, 300, 400]);
      expect(p0.cropBox, [50, 10, 400, 300]);
      expect(r.resolve((p0.resources['Font'] as CosDict)['F1']), isA<CosDict>());
      expect(p1.rotate, 270);
      expect(p1.mediaBox, [0, 0, 10, 20]);
      expect(p1.resources.entries, isEmpty);
      expect(p1.ref, const CosRef(7, 0));
    });

    test('/Prev chains: the newest incremental update wins', () {
      final pdf = RawPdf()
        ..obj(1, catalog)
        ..obj(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>')
        ..obj(3, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Contents 4 0 R >>')
        ..stream(4, '<< /Length 3 >>', latin1.encode('old'));
      final first = pdf.xrefTable('<< /Size 5 /Root 1 0 R >>');
      pdf
        ..stream(4, '<< /Length 3 >>', latin1.encode('mid'))
        ..obj(5, '<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>');
      final second = pdf.xrefTable('<< /Size 6 /Root 1 0 R /Prev $first >>', only: [4, 5]);
      pdf
        ..stream(4, '<< /Length 3 >>', latin1.encode('new'))
        ..obj(2, '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 /MediaBox [0 0 50 50] >>');
      pdf.xrefTable('<< /Size 6 /Prev $second >>', only: [2, 4]);
      final r = PdfSourceReader.parse(pdf.finish());
      expect(r.recoveredByScan, isFalse);
      expect(r.pageCount, 2);
      expect(contentOf(r, 0), 'new');
      expect(r.pages[1].mediaBox, [0, 0, 50, 50]);
    });

    Uint8List compressedFile({required bool predictor, bool hybrid = false}) {
      final pdf = RawPdf('1.5');
      final (data, first) = objectStreamData([
        (1, catalog),
        (2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
        (3, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Contents 4 0 R >>'),
      ]);
      final z = deflateText(latin1.decode(data));
      pdf
        ..stream(
          10,
          '<< /Type /ObjStm /N 3 /First $first /Filter /FlateDecode /Length 11 0 R >>',
          z,
        )
        ..obj(11, '${z.length}')
        ..stream(4, '<< /Length 24 >>', latin1.encode('0 0 1 rg 0 0 100 50 re f'));
      final rows = {
        for (final (i, n) in [1, 2, 3].indexed) n: [2, 10, i],
        5: [0, 0, 65535],
      };
      if (!hybrid) {
        rows.addAll({
          10: [1, pdf.offsets[10]!, 0],
          11: [1, pdf.offsets[11]!, 0],
          4: [1, pdf.offsets[4]!, 0],
        });
        pdf.xrefStream(12, rows, '/Root 1 0 R', predictor: predictor);
        return pdf.finish();
      }
      final stmAt = pdf.length;
      pdf.xrefStream(12, rows, '', predictor: predictor);
      pdf.xrefTable('<< /Size 13 /Root 1 0 R /XRefStm $stmAt >>', only: [4, 10, 11]);
      return pdf.finish();
    }

    test('xref streams with PNG predictor and object streams', () {
      for (final predictor in [false, true]) {
        final r = PdfSourceReader.parse(compressedFile(predictor: predictor));
        expect(r.recoveredByScan, isFalse);
        expect(r.pageCount, 1);
        expect(r.pages[0].mediaBox, [0, 0, 200, 100]);
        expect(r.getObject(5), isNull); // free entry
        expect(contentOf(r, 0), '0 0 1 rg 0 0 100 50 re f');
      }
    });

    test('hybrid files: classic table + /XRefStm', () {
      final r = PdfSourceReader.parse(compressedFile(predictor: true, hybrid: true));
      expect(r.recoveredByScan, isFalse);
      expect(r.pageCount, 1);
      expect(contentOf(r, 0), '0 0 1 rg 0 0 100 50 re f');
    });

    test('broken or missing xref: the file is scanned', () {
      final good = simpleFile();
      // No xref at all.
      final cut = latin1.decode(good).indexOf('xref');
      final noXref = PdfSourceReader.parse(Uint8List.sublistView(good, 0, cut));
      expect(noXref.recoveredByScan, isTrue);
      expect(noXref.pageCount, 1);
      expect(contentOf(noXref, 0), '1 0 0 rg 0 0 100 50 re f');
      // Wrong offsets in the table (every object shifted).
      final shifted = Uint8List.fromList([...b('%junk\n'), ...good]);
      final r = PdfSourceReader.parse(shifted);
      expect(r.pageCount, 1);
      expect(contentOf(r, 0), '1 0 0 rg 0 0 100 50 re f');
      // Object streams are found by the scan too.
      final comp = compressedFile(predictor: true);
      final at = latin1.decode(comp).lastIndexOf('startxref');
      final scanned = PdfSourceReader.parse(Uint8List.sublistView(comp, 0, at));
      expect(scanned.recoveredByScan, isTrue);
      expect(scanned.pageCount, 1);
    });

    test('encrypted files throw', () {
      final pdf = RawPdf()
        ..obj(1, catalog)
        ..obj(2, '<< /Type /Pages /Kids [] /Count 0 >>')
        ..obj(9, '<< /Filter /Standard /V 1 /R 2 >>');
      pdf.xrefTable('<< /Size 10 /Root 1 0 R /Encrypt 9 0 R >>');
      final bytes = pdf.finish();
      expect(() => PdfSourceReader.parse(bytes), throwsA(isA<PdfReadException>()));
      final cut = latin1.decode(bytes).indexOf('xref');
      final noXref = Uint8List.fromList([
        ...bytes.sublist(0, cut),
        ...b('trailer << /Root 1 0 R /Encrypt 9 0 R >>'),
      ]);
      expect(() => PdfSourceReader.parse(noXref), throwsA(isA<PdfReadException>()));
    });
  });

  group('rotation matrix', () {
    const crop = [10.0, 20.0, 210.0, 120.0]; // 200 × 100
    (double, double) apply(List<double> m, double x, double y) =>
        (m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]);

    for (final (rotate, topLeft, w, h) in [
      (0, (10.0, 120.0), 400.0, 200.0),
      (90, (10.0, 20.0), 200.0, 400.0),
      (180, (210.0, 20.0), 400.0, 200.0),
      (270, (210.0, 120.0), 200.0, 400.0),
      (-90, (210.0, 120.0), 200.0, 400.0),
    ]) {
      test('rotate $rotate', () {
        final m = ImportedPdfPage.pageMatrix(crop, rotate, w, h);
        final (u, v) = apply(m, topLeft.$1, topLeft.$2);
        expect(u, closeTo(0, 1e-9));
        expect(v, closeTo(h, 1e-9));
        final corners = {
          for (final (x, y) in [(10.0, 20.0), (210.0, 20.0), (10.0, 120.0), (210.0, 120.0)])
            apply(m, x, y),
        };
        expect(corners.map((c) => (c.$1.round(), c.$2.round())).toSet(), {
          (0, 0),
          (w.round(), 0),
          (0, h.round()),
          (w.round(), h.round()),
        });
      });
    }
  });

  group(
    'export through PDFium',
    skip: pdfium == null ? 'PDFium not built yet (run `flutter build linux` once)' : false,
    _e2e,
  );
}

/// Re-exports pages of [src] onto pages of their displayed size.
Future<Uint8List> reexport(Uint8List src, {PdfPageImporter? importer, pw.PdfDocument? doc}) {
  final reader = PdfSourceReader.parse(src);
  doc ??= pw.PdfDocument(compress: false, version: pw.PdfVersion.pdf_1_4);
  importer ??= PdfPageImporter(doc);
  for (var i = 0; i < reader.pageCount; i++) {
    final p = importer.importPage(reader, i);
    final size = p.displayedSize;
    final page = pw.PdfPage(doc, pageFormat: pw.PdfPageFormat(size.width, size.height));
    p.draw(page.getGraphics(), size.width, size.height);
  }
  return doc.save();
}

/// Renders page [index] at 2 px/pt: BGRA pixels, width, height.
Future<(Uint8List, int, int)> render(Uint8List pdf, int index, {double? w, double? h}) async {
  final doc = await rx.PdfDocument.openData(pdf);
  final page = doc.pages[index];
  final img = (await page.render(
    fullWidth: (w ?? page.width) * 2,
    fullHeight: (h ?? page.height) * 2,
  ))!;
  final result = (Uint8List.fromList(img.pixels), img.width, img.height);
  img.dispose();
  await doc.dispose();
  return result;
}

/// RGB at point ([x], [y]) from the top-left, in points (2 px/pt).
(int, int, int) rgbAt((Uint8List, int, int) r, double x, double y) {
  final i = ((y * 2).round() * r.$2 + (x * 2).round()) * 4;
  return (r.$1[i + 2], r.$1[i + 1], r.$1[i]);
}

/// Expects [out] page [outIndex] to render like [src] page [srcIndex].
Future<void> expectSameRender(
  Uint8List src,
  Uint8List out, [
  int srcIndex = 0,
  int outIndex = 0,
]) async {
  final o = await render(out, outIndex);
  final doc = await rx.PdfDocument.openData(out);
  final page = doc.pages[outIndex];
  final s = await render(src, srcIndex, w: page.width, h: page.height);
  await doc.dispose();
  expect((s.$2, s.$3), (o.$2, o.$3));
  var bad = 0;
  for (var i = 0; i < o.$1.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      if ((o.$1[i + c] - s.$1[i + c]).abs() > 60) {
        bad++;
        break;
      }
    }
  }
  expect(bad / (o.$2 * o.$3), lessThan(0.005), reason: 'pixels differing from the source render');
}

void _e2e() {
  setUpAll(() {
    rx.Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    rx.Pdfrx.pdfiumModulePath = pdfium;
  });

  Future<Uint8List> packagePdfSource({required bool compress}) {
    final doc = pw.PdfDocument(
      compress: compress,
      version: compress ? pw.PdfVersion.pdf_1_5 : pw.PdfVersion.pdf_1_4,
    );
    final font = pw.PdfFont.helvetica(doc);
    final image = pw.PdfImage(
      doc,
      image: Uint8List.fromList([
        255,
        0,
        0,
        255,
        0,
        255,
        0,
        255,
        0,
        0,
        255,
        255,
        255,
        255,
        255,
        255,
      ]),
      width: 2,
      height: 2,
    );
    for (var i = 0; i < 3; i++) {
      final page = pw.PdfPage(doc, pageFormat: const pw.PdfPageFormat(300, 200));
      page.getGraphics()
        ..drawImage(image, 0, 0, 100, 100)
        ..setFillColor(pw.PdfColors.black)
        ..drawString(font, 20, 'Hello Vector $i', 120, 150);
    }
    return doc.save();
  }

  for (final compress in [false, true]) {
    test(
      'package:pdf source (compress: $compress): text stays text, shared objects once',
      () async {
        final src = await packagePdfSource(compress: compress);
        final out = await reexport(src);
        final doc = await rx.PdfDocument.openData(out);
        expect(doc.pages, hasLength(3));
        for (var i = 0; i < 3; i++) {
          expect((await doc.pages[i].loadText())!.fullText, contains('Hello Vector $i'));
        }
        await doc.dispose();
        // Count fonts and images in the output with our own reader.
        final r = PdfSourceReader.parse(out);
        var fonts = 0, images = 0;
        for (var n = 1; n < (r.trailer['Size'].asInt ?? 0); n++) {
          final o = r.getObject(n);
          final d = o is CosStream ? o.dict : o;
          if (d is CosDict && d['Type'].asName == 'Font') fonts++;
          if (d is CosDict && d['Subtype'].asName == 'Image') images++;
        }
        expect(fonts, 1);
        expect(images, 2); // the image and its /SMask
        final px = await render(out, 1);
        expect(rgbAt(px, 25, 125), (255, 0, 0)); // image top-left: red
        expect(rgbAt(px, 75, 125), (0, 255, 0)); // image top-right: green
        expect(rgbAt(px, 25, 175), (0, 0, 255)); // image bottom-left: blue
        for (var i = 0; i < 3; i++) {
          await expectSameRender(src, out, i, i);
        }
      },
    );
  }

  test('xref-stream / object-stream source', () async {
    final pdf = RawPdf('1.5');
    final (data, first) = objectStreamData([
      (1, catalog),
      (2, '<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 200 100] >>'),
      (
        3,
        '<< /Type /Page /Parent 2 0 R /Contents 4 0 R /Resources << /ExtGState << /G 5 0 R >> >> >>',
      ),
      (5, '<< /Type /ExtGState /ca 1 >>'),
    ]);
    final z = deflateText(latin1.decode(data));
    const content = '/G gs 0 0 1 rg 0 0 100 50 re f';
    final cz = deflateText(content);
    pdf
      ..stream(
        10,
        '<< /Type /ObjStm /N 4 /First $first /Filter /FlateDecode /Length ${z.length} >>',
        z,
      )
      ..stream(4, '<< /Filter /FlateDecode /Length ${cz.length} >>', cz);
    pdf.xrefStream(
      11,
      {
        for (final (i, n) in [1, 2, 3, 5].indexed) n: [2, 10, i],
        10: [1, pdf.offsets[10]!, 0],
        4: [1, pdf.offsets[4]!, 0],
      },
      '/Root 1 0 R',
      predictor: true,
    );
    final src = pdf.finish();
    final out = await reexport(src);
    final px = await render(out, 0);
    expect(rgbAt(px, 50, 75), (0, 0, 255));
    expect(rgbAt(px, 150, 25), (255, 255, 255));
    await expectSameRender(src, out);
  });

  for (final rotate in [90, 180, 270, -90]) {
    test('rotated page /Rotate $rotate with an offset CropBox', () async {
      // Red in the unrotated top-left corner, blue in the bottom-left one.
      final src = simpleFile(
        pageExtra: '/Rotate $rotate /CropBox [10 0 210 110]',
        mediaBox: '[0 0 220 100]',
        content: '1 0 0 rg 10 80 20 20 re f 0 0 1 rg 10 0 20 20 re f',
      );
      final out = await reexport(src);
      final doc = await rx.PdfDocument.openData(out);
      final size = (doc.pages[0].width, doc.pages[0].height);
      await doc.dispose();
      expect(size, rotate % 180 == 0 ? (200.0, 100.0) : (100.0, 200.0));
      final px = await render(out, 0);
      final (red, blue) = switch ((rotate + 360) % 360) {
        90 => ((95.0, 5.0), (5.0, 5.0)),
        180 => ((195.0, 95.0), (195.0, 5.0)),
        _ => ((5.0, 195.0), (95.0, 195.0)),
      };
      expect(rgbAt(px, red.$1, red.$2), (255, 0, 0));
      expect(rgbAt(px, blue.$1, blue.$2), (0, 0, 255));
      await expectSameRender(src, out);
    });
  }

  test('annotation appearances are flattened (hidden ones and popups skipped)', () async {
    final pdf = RawPdf()
      ..obj(1, catalog)
      ..obj(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>')
      ..obj(
        3,
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Contents 4 0 R '
        '/Annots [5 0 R 8 0 R 9 0 R] >>',
      )
      ..stream(4, '<< /Length 0 >>', [])
      ..obj(
        5,
        '<< /Type /Annot /Subtype /Square /Rect [100 20 180 80] /P 3 0 R '
        '/AP << /N << /On 6 0 R /Off 7 0 R >> >> /AS /On >>',
      )
      ..stream(
        6,
        '<< /Type /XObject /Subtype /Form /BBox [0 0 10 10] /Matrix [0 2 -2 0 0 0] /Length 23 >>',
        latin1.encode('0 1 0 rg 0 0 5 10 re f '),
      )
      ..stream(7, '<< /BBox [0 0 10 10] /Length 23 >>', latin1.encode('1 0 0 rg 0 0 10 10 re f'))
      ..obj(8, '<< /Type /Annot /Subtype /Square /F 2 /Rect [0 0 50 50] /AP << /N 7 0 R >> >>')
      ..obj(9, '<< /Type /Annot /Subtype /Popup /Rect [0 50 50 100] /AP << /N 7 0 R >> >>');
    pdf.xrefTable('<< /Size 10 /Root 1 0 R >>');
    final src = pdf.finish();
    final out = await reexport(src);
    final px = await render(out, 0);
    // /Matrix maps (x, y) to (-2y, 2x): BBox becomes [-20 0 0 20], mapped onto
    // the Rect; the form's left half (x 0..5) fills the rect's bottom half.
    expect(rgbAt(px, 140, 65), (0, 255, 0));
    expect(rgbAt(px, 140, 30), (255, 255, 255));
    expect(rgbAt(px, 25, 75), (255, 255, 255)); // hidden
    expect(rgbAt(px, 25, 25), (255, 255, 255)); // popup
    await expectSameRender(src, out);
  });

  test('multiple content streams are decoded and concatenated', () async {
    final pdf = RawPdf()
      ..obj(1, catalog)
      ..obj(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>')
      ..obj(
        3,
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Contents [4 0 R 5 0 R 6 0 R] >>',
      );
    final z = deflateText('0 1 0');
    final hex = latin1.encode('72 67 20 30 20 30 20 35 30 20 35 30 20 72 65>');
    pdf
      ..stream(4, '<< /Filter /FlateDecode /Length ${z.length} >>', z)
      ..stream(5, '<< /Filter /ASCIIHexDecode /Length ${hex.length} >>', hex)
      ..stream(6, '<< /Length 2 >>', latin1.encode(' f'));
    pdf.xrefTable('<< /Size 7 /Root 1 0 R >>');
    final src = pdf.finish();
    final out = await reexport(src);
    final px = await render(out, 0);
    expect(rgbAt(px, 25, 75), (0, 255, 0));
    expect(rgbAt(px, 100, 25), (255, 255, 255));
    await expectSameRender(src, out);

    final lzw = RawPdf()
      ..obj(1, catalog)
      ..obj(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>')
      ..obj(3, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 9 9] /Contents [4 0 R 4 0 R] >>')
      ..stream(4, '<< /Filter /LZWDecode /Length 1 >>', [0]);
    lzw.xrefTable('<< /Size 5 /Root 1 0 R >>');
    final importer = PdfPageImporter(pw.PdfDocument());
    expect(
      () => importer.importPage(PdfSourceReader.parse(lzw.finish()), 0),
      throwsA(isA<PdfReadException>()),
    );
  });
}
