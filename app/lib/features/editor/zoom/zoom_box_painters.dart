import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/paper.dart';
import '../../../ink/render/paper_painter.dart';
import '../../../ink/viewport.dart';
import '../../../ui/app_theme.dart';
import '../document/document_layout.dart';
import '../document/document_painters.dart';
import '../document/page_painting.dart';
import '../editor_session.dart';
import 'zoom_window.dart';

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

/// The advance zone at the box's right (left when lines run right to
/// left): ink lifted there moves the frame on. A faint band in the paper's own pattern colour, with a hairline at
/// its start, so it reads as part of the paper rather than of the chrome.
/// While an advance waits for the pen to rest ([armed] rising to 1) it
/// deepens, so the move that follows is expected.
class ZoneBandPainter extends CustomPainter {
  ZoneBandPainter({
    required this.start,
    required this.paper,
    this.armed = 0,
    this.rightToLeft = false,
  });

  /// Where the zone starts (box pixels from the left).
  final double start;

  /// Whether the zone runs from [start] to the box's left edge.
  final bool rightToLeft;
  final PaperColor paper;

  /// How far a waiting advance has come (0 – 1).
  final double armed;

  /// How strongly the band tints the paper at rest and armed.
  static const double tint = 0.1, armedTint = 0.32;

  @override
  void paint(Canvas canvas, Size size) {
    if (rightToLeft ? start <= 0 : start >= size.width) return;
    final colour = paper.pattern;
    final band = rightToLeft
        ? Rect.fromLTRB(0, 0, start, size.height)
        : Rect.fromLTRB(start, 0, size.width, size.height);
    final edge = rightToLeft ? start - Hairline.width : start;
    canvas
      ..drawRect(band, Paint()..color = colour.withValues(alpha: tint + (armedTint - tint) * armed))
      ..drawRect(Rect.fromLTWH(edge, 0, Hairline.width, size.height), Paint()..color = colour);
  }

  @override
  bool shouldRepaint(ZoneBandPainter old) =>
      old.start != start ||
      old.paper != paper ||
      old.armed != armed ||
      old.rightToLeft != rightToLeft;
}

/// The advance zone's band, deepening over [ZoomWindow.pause] while an
/// advance waits (at once with reduced motion) and clearing quickly.
class ZoneBand extends StatelessWidget {
  const ZoneBand({
    super.key,
    required this.armed,
    required this.start,
    required this.paper,
    this.rightToLeft = false,
  });

  /// Whether an advance waits ([ZoomWindow.armed]).
  final ValueListenable<bool> armed;

  /// Where the zone starts (box pixels from the left).
  final double start;
  final PaperColor paper;

  /// Whether the zone lies left of [start] (lines run right to left).
  final bool rightToLeft;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: armed,
    builder: (context, on, _) => TweenAnimationBuilder<double>(
      tween: Tween(end: on ? 1 : 0),
      duration: Motion.reduced(context)
          ? Duration.zero
          : on
          ? ZoomWindow.pause
          : Motion.fast,
      builder: (context, t, _) => CustomPaint(
        painter: ZoneBandPainter(start: start, paper: paper, armed: t, rightToLeft: rightToLeft),
      ),
    ),
  );
}
