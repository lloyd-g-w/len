part of 'version_surface_view.dart';

/// A [VersionSurfaceView]'s picture: as wide as it can be at its sheet's
/// shape, a layer of its own (painted once, a canvas's thousands of
/// strokes too, not with every frame of the list around it). One render
/// object, laid out again and repainted as what it shows arrives, with no
/// rebuild.
class _SheetBox extends LeafRenderObjectWidget {
  const _SheetBox(this.painter);

  final _SheetPainter painter;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSheet(painter);

  @override
  void updateRenderObject(BuildContext context, _RenderSheet renderObject) =>
      renderObject.painter = painter;
}

class _RenderSheet extends RenderAspectRatio {
  _RenderSheet(this._painter) : super(aspectRatio: _painter.picture.ratio);

  _SheetPainter _painter;
  set painter(_SheetPainter value) {
    if (identical(value, _painter)) return;
    final old = _painter;
    _painter = value;
    if (attached) {
      old.removeListener(_changed);
      value.addListener(_changed);
    }
    aspectRatio = value.picture.ratio;
    if (value.shouldRepaint(old)) markNeedsPaint();
  }

  void _changed() {
    aspectRatio = _painter.picture.ratio;
    markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => true;

  /// Taps on it are its tile's or row's.
  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _painter.addListener(_changed);
  }

  @override
  void detach() {
    _painter.removeListener(_changed);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    _painter.paint(canvas, size);
    canvas.restore();
  }
}

class _SheetPainter extends CustomPainter {
  _SheetPainter(
    this.picture,
    this.view,
    this.images,
    this.version,
    this.page,
    this.backgrounds,
    this.dpr,
    this.brightness,
  ) : super(repaint: Listenable.merge([picture, ?backgrounds]));

  /// What has loaded (it repaints this as it does).
  final _SheetPicture picture;

  /// Where the ink image of a large sheet's thumbnail is asked for.
  final VersionSurfaceViewState view;
  final ElementImages images;
  final NotebookVersion? version;
  final VersionPage? page;
  final PageBackgrounds? backgrounds;
  final double dpr;

  /// The theme's, for the shadow of the paper on the desk.
  final Brightness brightness;

  /// Pictures up to this wide are thumbnails (the history's rows).
  static const thumbnailWidth = 96.0;

  @override
  void paint(Canvas canvas, Size size) {
    // The paper resting on the desk: its shadow outside the clip, so it
    // keeps its edge on a light sheet.
    final paper = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(Radii.xs));
    for (final shadow in Shadows.low(brightness)) {
      canvas.drawRRect(paper.shift(shadow.offset).inflate(shadow.spreadRadius), shadow.toPaint());
    }
    canvas
      ..save()
      ..clipRRect(paper);
    _paintSheet(canvas, size);
    canvas.restore();
  }

  void _paintSheet(Canvas canvas, Size size) {
    final sheet = picture.sheet;
    if (sheet != null) picture.painted = true;
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
    final ink = sheet == null ? null : view._inkAt(sheet, size, dpr);
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
      !identical(old.picture, picture) ||
      old.version?.id != version?.id ||
      old.page != page ||
      old.backgrounds != backgrounds ||
      old.dpr != dpr ||
      old.brightness != brightness;
}
