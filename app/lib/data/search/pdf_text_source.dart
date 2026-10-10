import 'dart:typed_data';
import 'dart:ui';

import 'package:pdfrx/pdfrx.dart';

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
  /// unavailable (rotated pages). Boxes are normalised to the page: 0..1
  /// from the left and top edges.
  Future<PdfGlyphs?> glyphs(int index);

  Future<void> dispose();
}

/// A page's text and the box of every UTF-16 unit of it.
class PdfGlyphs {
  const PdfGlyphs(this.text, this.boxes) : assert(text.length == boxes.length);

  final String text;

  /// Normalised (0..1, top-left origin) box of each unit of [text].
  final List<Rect> boxes;

  /// Boxes covering `text[start..end)`, merged into one per line.
  List<Rect> rectsFor(int start, int end) {
    final lines = <Rect>[];
    for (var i = start.clamp(0, boxes.length); i < end.clamp(0, boxes.length); i++) {
      final box = boxes[i];
      if (box.isEmpty) continue; // Spaces and line breaks have no box.
      final last = lines.isEmpty ? null : lines.last;
      // Same line: vertical overlap of more than half the shorter height.
      if (last != null &&
          box.left >= last.left - box.height &&
          (box.bottom < last.bottom ? box.bottom : last.bottom) -
                  (box.top > last.top ? box.top : last.top) >
              0.5 * (box.height < last.height ? box.height : last.height)) {
        lines[lines.length - 1] = last.expandToInclude(box);
      } else {
        lines.add(box);
      }
    }
    return lines;
  }
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
  Future<PdfGlyphs?> glyphs(int index) async {
    final page = _doc.pages[index];
    if (page.rotation != PdfPageRotation.none || page.width <= 0 || page.height <= 0) return null;
    final raw = await page.loadText();
    if (raw == null || raw.fullText.length != raw.charRects.length) return null;
    return PdfGlyphs(raw.fullText, [
      for (final r in raw.charRects)
        Rect.fromLTRB(
          r.left / page.width,
          1 - r.top / page.height,
          r.right / page.width,
          1 - r.bottom / page.height,
        ),
    ]);
  }

  @override
  Future<void> dispose() => _doc.dispose();
}
