import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../ink/images/image_pixel.dart';
import '../../../ink/surface_model.dart';
import '../../../ink/tools/content_colour.dart';
import '../editor_session.dart';
import 'page_snapshot.dart';

/// A point of a surface on screen: its model, the point in surface units,
/// the paper's colour and the view's scale (screen pixels per unit).
typedef SurfacePoint = ({SurfaceModel model, Offset local, Color paper, double scale});

/// What the eyedropper reads in one editor: whether a point on screen is
/// on the page (not chrome, not the desk between pages) and the colour
/// there ([ContentColour], else the page as rendered, else its paper).
class PageColours {
  PageColours({required this.session, required this.canvas, required this.area});

  final EditorSession session;

  /// The surface's [RepaintBoundary] (what [PageSnapshot] captures).
  final GlobalKey canvas;

  /// The editor's layers (surface, overlays, chrome), to tell what is on top.
  final GlobalKey area;

  RenderBox? get _canvasBox => canvas.currentContext?.findRenderObject() as RenderBox?;

  /// The surface's box on screen (global).
  Rect? get bounds {
    final box = _canvasBox;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// The part of [bounds] the chrome along the edges leaves free.
  Rect? get free => bounds == null ? null : session.chromeInsets.deflateRect(bounds!);

  /// Whether [global] is on the page: the surface is the topmost thing
  /// there (no chrome, menu or panel over it) and, in a paged document, a
  /// page lies under it.
  bool onPage(Offset global) {
    final box = _canvasBox;
    final layers = area.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || layers == null || !layers.attached || !box.attached) return false;
    final result = BoxHitTestResult();
    layers.hitTest(result, position: layers.globalToLocal(global));
    // The layers are hit top down until one takes the hit; those above it
    // that only listen along (translucent: the PDF text layer…) come
    // first in the path. So the layer of the last entry took it.
    RenderObject? taker;
    for (final entry in result.path) {
      if (entry.target case final RenderObject target) taker = _layerOf(target, layers) ?? taker;
    }
    return taker == box && surfaceAt(global) != null;
  }

  /// The child of [layers] holding [node]; null for [layers] itself and
  /// what lies outside it.
  static RenderObject? _layerOf(RenderObject node, RenderObject layers) {
    for (RenderObject? n = node; n != null; n = n.parent) {
      if (n.parent == layers) return n;
    }
    return null;
  }

  /// The surface point under [global], if a surface is there.
  SurfacePoint? surfaceAt(Offset global) {
    final box = _canvasBox;
    if (box == null || !box.attached) return null;
    final screen = box.globalToLocal(global);
    final doc = session.doc;
    if (doc == null) {
      final viewport = session.canvasViewport!;
      return (
        model: session.canvas!,
        local: viewport.toWorld(screen),
        paper: session.notebook.paperColor.paper,
        scale: viewport.scale,
      );
    }
    final world = doc.viewport.toWorld(screen);
    final index = doc.layout.pageAt(world);
    if (index == null) return null;
    final model = doc.surfaces.peek(doc.pages[index].id)?.model;
    final frame = doc.layout.frameOf(index);
    if (model == null || frame == null) return null;
    return (
      model: model,
      local: world - frame.topLeft,
      paper: doc.pages[index].paperColor.paper,
      scale: doc.viewport.scale,
    );
  }

  /// The colour at [global] (opaque ARGB): the content's own colour; where
  /// none is (or only translucent tints), the page as [snapshot] shows it,
  /// else the paper's colour. Null off the page.
  Future<int?> colourAt(Offset global, {PageSnapshot? snapshot, double dpr = 1}) async {
    final point = surfaceAt(global);
    if (point == null) return null;
    final content = await ContentColour.at(
      point.model,
      point.local,
      tolerance: _tolerance / point.scale,
      pixelScale: point.scale * dpr,
      imagePixel: (image, uv, width) => ImagePixels.read(session.services.images, image, uv, width),
    );
    if (content != null && content >>> 24 == 0xFF) return content;
    if (snapshot?.pixelAt(global) case final pixel?) return pixel;
    final paper = point.paper;
    if (content == null) return paper.toARGB32();
    return Color.alphaBlend(Color(content), paper).toARGB32();
  }

  /// How far (screen pixels) past a stroke's edge a pick still takes it.
  static const double _tolerance = 1.5;
}
