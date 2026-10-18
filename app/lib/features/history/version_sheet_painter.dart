part of 'version_surface_view.dart';

class _SheetPainter extends CustomPainter {
  _SheetPainter(
    this.sheet,
    this.images,
    this.version,
    this.page,
    this.backgrounds,
    this.dpr,
    this.imagesShown, {
    this.ink,
  }) : super(repaint: backgrounds);

  final VersionSheet? sheet;
  final ElementImages images;
  final NotebookVersion? version;
  final VersionPage? page;
  final PageBackgrounds? backgrounds;
  final double dpr;
  final int imagesShown;

  /// A large sheet's thumbnail: its ink drawn from this image (null while
  /// it renders: the paper shows meanwhile), not stroke by stroke.
  final ({ui.Image? image, InkImageKey key})? ink;

  /// Pictures up to this wide are thumbnails (the history's rows).
  static const thumbnailWidth = 96.0;

  @override
  void paint(Canvas canvas, Size size) {
    final sheet = this.sheet;
    final version = this.version;
    final page =
        sheet?.page ??
        (version != null && this.page != null ? VersionContent.pageOf(version, this.page!) : null);
    if (page == null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = PaperColor.white.paper);
      return;
    }
    final scale = size.width / page.width;
    final origin = sheet?.origin;
    // In a thumbnail, ink too thin to show as more than a line is drawn as
    // one: outlines take ~0.3 ms a stroke to build, on this thread.
    final thumbnail = size.width <= thumbnailWidth;
    final bg = page.background;
    final image = bg == null ? null : backgrounds?.imageFor(bg, size.width * dpr);
    canvas
      ..save()
      ..scale(scale);
    final ink = this.ink;
    // Its content painted below, in the frame; pages' at once with their paper.
    final direct = ink == null && origin == null;
    paintWholePage(
      canvas,
      page,
      strokes: direct ? sheet?.strokes ?? const [] : const [],
      elements: direct ? sheet?.elements ?? const [] : const [],
      scale: scale,
      background: image,
      images: images,
      miniature: true,
      worldOrigin: origin,
      sketchThin: thumbnail,
    );
    if (sheet != null && !direct) {
      final from = origin ?? Offset.zero;
      canvas
        ..save()
        ..clipRect(Offset.zero & page.size)
        ..translate(-from.dx, -from.dy);
      if (ink == null) {
        // A canvas: its content where it is, moved into the frame.
        ContentPainter.paint(
          canvas,
          sheet.strokes,
          sheet.elements,
          images: images,
          pixelScale: scale,
          sketchThin: thumbnail,
        );
      } else {
        _paintWithInk(canvas, sheet, ink.image, ink.key.frame, scale);
      }
      canvas.restore();
    }
    if (bg != null && image == null && (backgrounds?.isMissing(bg) ?? false)) {
      paintMissingPdf(canvas, page.size, scan: !bg.isPdf);
    }
    canvas.restore();
  }

  /// [sheet]'s elements around its ink drawn from [image] (of [frame]).
  void _paintWithInk(Canvas canvas, VersionSheet sheet, ui.Image? image, Rect frame, double scale) {
    void elements(bool belowInk) => ContentPainter.paint(
      canvas,
      const [],
      [
        for (final e in sheet.elements)
          if (e.belowInk == belowInk) e,
      ],
      images: images,
      pixelScale: scale,
    );
    elements(true);
    if (image != null) {
      final source = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
      canvas.drawImageRect(image, source, frame, Paint()..filterQuality = FilterQuality.low);
    }
    elements(false);
  }

  @override
  bool shouldRepaint(_SheetPainter old) =>
      !identical(old.sheet, sheet) ||
      old.version?.id != version?.id ||
      old.page != page ||
      old.backgrounds != backgrounds ||
      old.dpr != dpr ||
      old.imagesShown != imagesShown ||
      old.ink?.image != ink?.image ||
      old.ink?.key != ink?.key;
}
