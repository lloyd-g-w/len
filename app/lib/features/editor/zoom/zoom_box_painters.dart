import 'package:flutter/material.dart';

import '../../../domain/paper.dart';
import '../../../ink/render/paper_painter.dart';
import '../../../ink/viewport.dart';
import '../../../ui/app_theme.dart';
import '../document/document_layout.dart';
import '../document/document_painters.dart';
import '../document/page_painting.dart';
import '../editor_session.dart';

/// The paper under the box: the frame's page as the page view draws it
/// (template, PDF page, image template, the desk around it), or the
/// canvas's background.
CustomPainter zoomPaperPainter(
  BuildContext context,
  EditorSession session,
  String surfaceId,
  ViewportController view,
) {
  final doc = session.doc;
  if (doc == null) {
    final notebook = session.notebook;
    return PaperPainter(viewport: view, paper: notebook.paper, paperColor: notebook.paperColor);
  }
  final index = doc.pages.indexWhere((p) => p.id == surfaceId);
  final brightness = Theme.of(context).brightness;
  final images = doc.surfaces.images;
  return DocumentPaperPainter(
    // The page alone, at its own origin: the box's viewport is the page's.
    layout: index == -1
        ? DocumentLayout.continuous(const [])
        : DocumentLayout.single(index, doc.pages[index].size),
    pages: doc.pages,
    viewport: view,
    desk: Surfaces.canvasBackdrop(brightness),
    shadows: Shadows.low(brightness),
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    backgrounds: session.backgrounds,
    paperImages: images == null ? null : paperImagesOf(images),
  );
}

/// The advance zone at the box's right: ink lifted there moves the frame
/// on. A faint band in the paper's own pattern colour, with a rule at its
/// start, so it reads as part of the paper rather than of the chrome.
class ZoneBandPainter extends CustomPainter {
  ZoneBandPainter({required this.start, required this.paper});

  /// Where the zone starts (box pixels from the left).
  final double start;
  final PaperColor paper;

  /// How strongly the band tints the paper.
  static const double tint = 0.22;

  @override
  void paint(Canvas canvas, Size size) {
    if (start >= size.width) return;
    final colour = paper.pattern;
    canvas
      ..drawRect(
        Rect.fromLTRB(start, 0, size.width, size.height),
        Paint()..color = colour.withValues(alpha: tint),
      )
      ..drawRect(Rect.fromLTWH(start, 0, Hairline.width, size.height), Paint()..color = colour);
  }

  @override
  bool shouldRepaint(ZoneBandPainter old) => old.start != start || old.paper != paper;
}
