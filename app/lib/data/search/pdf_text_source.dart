import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:pdfrx/pdfrx.dart';

import '../../domain/pdf_page_space.dart';
import 'pdf_glyphs.dart';

export 'pdf_glyphs.dart';

/// Reads the text of PDF files (an interface so tests can fake PDFium).
abstract interface class PdfTextSource {
  /// Opens the PDF [bytes]; throws if they are not a readable PDF.
  Future<PdfTextDocument> open(Uint8List bytes);
}

/// An open PDF whose page text can be read.
abstract interface class PdfTextDocument {
  int get pageCount;

  /// The text of page [index] (zero-based), as PDFium extracts it.
  Future<String> pageText(int index);

  /// The text of page [index] with a box per UTF-16 unit, or null when
  /// unavailable. Boxes are normalised to the page as shown (rotated by
  /// its `/Rotate`): 0..1 from the left and top edges.
  Future<PdfGlyphs?> glyphs(int index);

  Future<void> dispose();
}

/// The text of PDFium [page] with its character boxes normalised to the
/// page as shown, or null if it has none.
Future<PdfGlyphs?> pdfiumGlyphs(PdfPage page) async {
  if (page.width <= 0 || page.height <= 0) return null;
  final raw = await page.loadText();
  if (raw == null || raw.fullText.length != raw.charRects.length) return null;
  return PdfGlyphs(raw.fullText, [for (final r in raw.charRects) pdfiumRectToDisplay(r, page)]);
}

/// Normalises [r], in PDFium's page space (before rotation, origin at the
/// page box's lower-left corner), to [page] as shown.
Rect pdfiumRectToDisplay(PdfRect r, PdfPage page) {
  final turns = page.rotation.index;
  final swap = turns.isOdd;
  return pdfRectToDisplay(
    r.left,
    r.bottom,
    r.right,
    r.top,
    width: swap ? page.height : page.width,
    height: swap ? page.width : page.height,
    quarterTurns: turns,
  );
}

/// [PdfTextSource] backed by PDFium through `pdfrx` (Android, Linux,
/// Windows, and its WebAssembly build in browsers).
class PdfrxTextSource implements PdfTextSource {
  const PdfrxTextSource();

  @override
  Future<PdfTextDocument> open(Uint8List bytes) async {
    await pdfrxFlutterInitialize();
    return _PdfrxTextDocument(await PdfDocument.openData(bytes, sourceName: 'search'));
  }
}

class _PdfrxTextDocument implements PdfTextDocument {
  _PdfrxTextDocument(this._doc);

  final PdfDocument _doc;

  @override
  int get pageCount => _doc.pages.length;

  @override
  Future<String> pageText(int index) async => (await _doc.pages[index].loadText())?.fullText ?? '';

  @override
  Future<PdfGlyphs?> glyphs(int index) => pdfiumGlyphs(_doc.pages[index]);

  @override
  Future<void> dispose() => _doc.dispose();
}
