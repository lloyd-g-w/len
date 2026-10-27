import 'dart:async';
import 'dart:ui' as ui;
import 'dart:ui' show Canvas, Offset, Rect, Size;

import 'package:flutter/foundation.dart';

import '../../../domain/image_data.dart';
import '../../../domain/notebook_page.dart';
import '../../../ink/images/element_images.dart';
import '../../documents/pdf/pdf_background_cache.dart';
import 'document_painters.dart';
import 'missing_pdf_painter.dart';
import 'page_backgrounds.dart';

/// The page backgrounds of a notebook: PDF pages from [pdf], images
/// (scanned documents) from the app's shared [images] cache, decoded at
/// the size they are drawn (mip levels, see [ElementImages]).
class NotebookBackgrounds extends ChangeNotifier implements PageBackgrounds {
  NotebookBackgrounds({required this.pdf, required this.images}) {
    pdf.addListener(notifyListeners);
    _changes = images.changes.listen((blob) {
      if (_asked.contains(blob)) notifyListeners();
    });
  }

  /// Rendered PDF pages (owned: disposed with this).
  final PdfBackgroundCache pdf;

  /// Decoded images (the app's, shared with image elements).
  final ElementImages images;

  /// Image backgrounds asked for: their decodes repaint the pages.
  final Set<String> _asked = {};
  late final StreamSubscription<String> _changes;

  @override
  ui.Image? imageFor(PageBackground background, double pixelWidth) =>
      background.isPdf ? pdf.imageFor(background, pixelWidth) : _image(background, pixelWidth);

  @override
  void paint(
    Canvas canvas,
    PageBackground background,
    Size page,
    Rect visible,
    double pixelsPerUnit, {
    int rank = 0,
  }) {
    if (background.isPdf) {
      return pdf.paint(canvas, background, page, visible, pixelsPerUnit, rank: rank);
    }
    if (rank == 0) pdf.beginFrame();
    final image = _image(background, page.width * pixelsPerUnit);
    if (image != null) {
      paintBackgroundImage(canvas, image, Offset.zero & page);
    } else if (images.isMissing(background.blob)) {
      paintMissingPdf(canvas, page, scan: true);
    }
  }

  @override
  void prefetch(PageBackground background, Size page, double pixelsPerUnit, {required bool after}) {
    if (background.isPdf) pdf.prefetch(background, page, pixelsPerUnit, after: after);
  }

  @override
  bool isMissing(PageBackground background) =>
      background.isPdf ? pdf.isMissing(background) : images.isMissing(background.blob);

  ui.Image? _image(PageBackground background, double pixelWidth) {
    _asked.add(background.blob);
    return images.imageFor(ImageData(blob: background.blob, width: 0, height: 0), pixelWidth);
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    pdf
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}
