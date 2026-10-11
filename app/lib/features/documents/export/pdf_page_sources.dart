
import 'package:flutter/foundation.dart';

import 'vector/pdf_source_reader.dart';

/// Reads the bytes of a PDF blob, or null when unavailable.
typedef PdfBlobReader = Future<Uint8List?> Function(String sha);

/// Rewrites a PDF blob through PDFium (decrypted, repaired); null if that
/// fails too. See `PdfRenderer.normalized`.
typedef PdfNormalizer = Future<Uint8List?> Function(String sha);

/// The source PDFs of imported pages during one export, parsed once each
/// so their pages can be copied into the export as vectors.
///
/// A blob is parsed as stored; if Len's PDF reader cannot handle it (e.g.
/// it is encrypted with an empty user password, or badly damaged), PDFium
/// rewrites it first and the rewrite is parsed. If that fails as well, the
/// blob has no source and its pages are exported as images.
class PdfPageSources {
  PdfPageSources({required this.read, required this.normalize});

  final PdfBlobReader read;
  final PdfNormalizer normalize;

  final Map<String, Future<PdfSourceReader?>> _sources = {};

  /// The parsed PDF blob [sha], or null if its pages must be rasterised.
  Future<PdfSourceReader?> sourceOf(String sha) => _sources[sha] ??= _load(sha);

  Future<PdfSourceReader?> _load(String sha) async {
    final bytes = await read(sha);
    if (bytes == null) return null;
    try {
      return PdfSourceReader.parse(bytes);
    } catch (e) {
      // Unsupported or malformed input (the reader may fail in any way).
      debugPrint('PDF $sha needs PDFium to be copied: $e');
    }
    try {
      final rewritten = await normalize(sha);
      return rewritten == null ? null : PdfSourceReader.parse(rewritten);
    } catch (e) {
      debugPrint('PDF $sha will be exported as images: $e');
      return null;
    }
  }
}
