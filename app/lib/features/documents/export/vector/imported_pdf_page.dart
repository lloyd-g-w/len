/// A source PDF page copied into a `package:pdf` document as Form XObjects.
library;

import 'dart:typed_data';

import 'package:flutter/rendering.dart' show Matrix4, Size;
import 'package:pdf/pdf.dart' as pw;
// ignore: implementation_imports
import 'package:pdf/src/pdf/obj/formxobject.dart' as pw;
// ignore: implementation_imports
import 'package:pdf/src/priv.dart' as pw;

/// A Form XObject written with a caller-supplied dictionary and raw stream
/// bytes (already encoded when the dictionary has a `/Filter`).
class RawFormXObject extends pw.PdfFormXObject {
  /// Creates the form in [document]; `/Type`, `/Subtype` and `/Length` are set
  /// on output.
  RawFormXObject(super.document, this.values, this.data);

  /// The form dictionary entries (keys with a leading slash).
  final Map<String, pw.PdfDataType> values;

  /// The stream bytes.
  final Uint8List data;

  @override
  void writeContent(pw.PdfStream s) {
    final v = {
      ...values,
      '/Type': const pw.PdfName('/XObject'),
      '/Subtype': const pw.PdfName('/Form'),
    }..remove('/Length');
    if (!v.containsKey('/Filter')) v.remove('/DecodeParms');
    pw.PdfDictStream(values: v, data: data).output(this, s, settings.verbose ? 0 : null);
    s.putByte(0x0a);
  }
}

/// A flattened annotation appearance: a form drawn with [matrix] in the
/// source page's default user space.
class AnnotationAppearance {
  /// Creates an appearance placement.
  AnnotationAppearance(this.form, this.matrix);

  /// The copied appearance stream.
  final pw.PdfFormXObject form;

  /// The matrix `[a b c d e f]` mapping form space (after its `/Matrix`) to
  /// page space (PDF 32000-1 §12.5.5 matrix A).
  final List<double> matrix;
}

/// A page imported by `PdfPageImporter`, ready to be drawn on target pages.
class ImportedPdfPage {
  /// Creates an imported page; normally done by `PdfPageImporter.importPage`.
  ImportedPdfPage({
    required this.content,
    required this.annotations,
    required this.cropBox,
    required this.rotate,
  });

  /// The page content as a form whose `/BBox` is [cropBox].
  final pw.PdfFormXObject content;

  /// Flattened annotation appearances, drawn above [content] in order.
  final List<AnnotationAppearance> annotations;

  /// The visible region `[x0, y0, x1, y1]` in source page space.
  final List<double> cropBox;

  /// The page rotation: 0, 90, 180 or 270 (clockwise when displayed).
  final int rotate;

  /// The displayed page size in points, with [rotate] applied.
  Size get displayedSize {
    final w = cropBox[2] - cropBox[0], h = cropBox[3] - cropBox[1];
    return rotate % 180 == 0 ? Size(w, h) : Size(h, w);
  }

  /// Draws the page (and its annotation appearances) filling the rectangle
  /// `[0, 0, width, height]` of the target page (points, y up), rotated by
  /// [rotate] and scaled independently along x and y.
  void draw(pw.PdfGraphics g, double width, double height) {
    final m = pageMatrix(cropBox, rotate, width, height);
    g
      ..saveContext()
      ..setTransform(_matrix4(m))
      ..drawRect(cropBox[0], cropBox[1], cropBox[2] - cropBox[0], cropBox[3] - cropBox[1])
      ..clipPath()
      ..drawXObject(content, 0, 0);
    for (final a in annotations) {
      g
        ..saveContext()
        ..setTransform(_matrix4(a.matrix))
        ..drawXObject(a.form, 0, 0)
        ..restoreContext();
    }
    g.restoreContext();
  }

  /// The matrix `[a b c d e f]` mapping source page space onto the target
  /// rectangle `[0, 0, width, height]` for a page with [cropBox] `[x0 y0 x1 y1]`
  /// shown rotated clockwise by [rotate] degrees (0, 90, 180 or 270).
  static List<double> pageMatrix(List<double> cropBox, int rotate, double width, double height) {
    final [x0, y0, x1, y1] = cropBox;
    final cw = x1 - x0, ch = y1 - y0;
    final r = ((rotate ~/ 90) % 4 + 4) % 4;
    final sx = width / (r.isEven ? cw : ch);
    final sy = height / (r.isEven ? ch : cw);
    return switch (r) {
      0 => [sx, 0, 0, sy, -sx * x0, -sy * y0],
      1 => [0, -sy, sx, 0, -sx * y0, sy * x1],
      2 => [-sx, 0, 0, -sy, sx * x1, sy * y1],
      _ => [0, sy, -sx, 0, sx * y1, -sy * x0],
    };
  }

  static Matrix4 _matrix4(List<double> m) =>
      Matrix4(m[0], m[1], 0, 0, m[2], m[3], 0, 0, 0, 0, 1, 0, m[4], m[5], 0, 1);
}
