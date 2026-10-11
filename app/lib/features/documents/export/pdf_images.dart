import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show Matrix4;
import 'package:pdf/pdf.dart';

import '../../../domain/image_data.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/images/element_images.dart';
import '../../editor/images/image_import.dart';

/// Writes image elements into a PDF at their full stored resolution.
///
/// JPEG blobs are embedded as they are (no re-compression, EXIF
/// orientation honoured); other formats are decoded and embedded as
/// pixels with their transparency. The element's rotation becomes a PDF
/// transform and its crop a clip, so the page shows exactly the part of
/// the image seen in the app.
class PdfImageWriter {
  PdfImageWriter(this.doc, this.readBlob);

  final PdfDocument doc;

  /// The bytes of a blob, or null when unavailable.
  final Future<Uint8List?> Function(String sha) readBlob;

  /// Each blob is embedded once per document, however often it is used.
  final Map<String, PdfImage?> _embedded = {};

  /// Draws [element] (an image) onto [g]; [toPdf] maps world points to PDF
  /// points and [k] is PDF points per world unit.
  Future<void> draw(
    PdfGraphics g,
    SurfaceElement element, {
    required ui.Offset Function(ui.Offset) toPdf,
    required double k,
  }) async {
    final data = ImageData.fromJson(element.data);
    final image = await _imageOf(data.blob);
    if (image == null) return;
    final crop = data.crop;
    final w = element.rect.width * k, h = element.rect.height * k;
    final fullW = w / crop.width, fullH = h / crop.height;
    final centre = toPdf(element.rect.center);
    // PDF y points up, so a clockwise rotation in the app is negative here.
    final t = Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..rotateZ(-element.rotation);
    g
      ..saveContext()
      ..setTransform(t)
      ..drawRect(-w / 2, -h / 2, w, h)
      ..clipPath()
      ..drawImage(image, -w / 2 - crop.left * fullW, h / 2 + crop.top * fullH - fullH, fullW, fullH)
      ..restoreContext();
  }

  /// Draws image [blob] stretched over the whole page (an image template,
  /// as `PaperRenderer` paints it) of [width] × [height] points; nothing
  /// if the blob is unavailable.
  Future<void> drawPage(PdfGraphics g, String blob, double width, double height) async {
    final image = await _imageOf(blob);
    if (image != null) g.drawImage(image, 0, 0, width, height);
  }

  Future<PdfImage?> _imageOf(String blob) async {
    if (_embedded.containsKey(blob)) return _embedded[blob];
    PdfImage? image;
    try {
      final bytes = blob.isEmpty ? null : await readBlob(blob);
      if (bytes != null) image = await _embed(bytes);
    } on Object catch (e) {
      debugPrint('Cannot embed image $blob: $e');
    }
    return _embedded[blob] = image;
  }

  Future<PdfImage> _embed(Uint8List bytes) async {
    if (ImageImport.sniff(bytes) == 'image/jpeg') return PdfImage.jpeg(doc, image: bytes);
    final decoded = await ElementImages.decode(bytes, width: ElementImages.maxWidth);
    try {
      final rgba = await decoded.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      return PdfImage(
        doc,
        image: rgba!.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
        width: decoded.width,
        height: decoded.height,
      );
    } finally {
      decoded.dispose();
    }
  }
}
