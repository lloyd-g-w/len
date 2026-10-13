import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../domain/notebook_page.dart';
import 'missing_pdf_painter.dart';
import 'page_backgrounds.dart';
import 'page_painting.dart';
import 'page_thumbnail_cache.dart';

export 'page_thumbnail_cache.dart';

/// A read-only miniature of a page: paper, background, template and ink.
class PageThumbnail extends StatelessWidget {
  const PageThumbnail({super.key, required this.page, required this.cache, this.backgrounds});

  final NotebookPage page;
  final ThumbnailCache cache;
  final PageBackgrounds? backgrounds;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: page.width / page.height,
      child: ListenableBuilder(
        listenable: cache,
        builder: (context, _) => CustomPaint(
          painter: _ThumbnailPainter(
            page,
            cache.inkOf(page.id),
            cache,
            backgrounds,
            MediaQuery.devicePixelRatioOf(context),
          ),
        ),
      ),
    );
  }
}

class _ThumbnailPainter extends CustomPainter {
  _ThumbnailPainter(this.page, this.ink, this.cache, this.backgrounds, this.dpr)
    : super(repaint: Listenable.merge([cache, backgrounds]));

  final NotebookPage page;
  final ui.Picture? ink;
  final ThumbnailCache cache;
  final PageBackgrounds? backgrounds;
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / page.width;
    final bg = page.background;
    final image = bg == null ? null : backgrounds?.imageFor(bg, size.width * dpr);
    canvas
      ..save()
      ..scale(scale);
    paintWholePage(
      canvas,
      page,
      strokes: const [],
      scale: scale,
      background: image,
      miniature: true,
      paperImages: (blob, _) => cache.paperImage(blob, size.width * dpr),
    );
    if (bg != null && image == null && (backgrounds?.isMissing(bg) ?? false)) {
      paintMissingPdf(canvas, page.size);
    }
    final raster = cache.rasterOf(
      page.id,
      page.size,
      (size.width * dpr).ceil(),
      (size.height * dpr).ceil(),
    );
    if (raster != null) {
      canvas.drawImageRect(
        raster,
        Rect.fromLTWH(0, 0, raster.width.toDouble(), raster.height.toDouble()),
        Offset.zero & page.size,
        _rasterPaint,
      );
    } else if (ink case final ink?) {
      canvas
        ..clipRect(Offset.zero & page.size)
        ..drawPicture(ink);
    }
    canvas.restore();
  }

  static final Paint _rasterPaint = Paint()..filterQuality = FilterQuality.medium;

  @override
  bool shouldRepaint(_ThumbnailPainter old) =>
      old.page != page ||
      old.ink != ink ||
      old.cache != cache ||
      old.backgrounds != backgrounds ||
      old.dpr != dpr;
}
