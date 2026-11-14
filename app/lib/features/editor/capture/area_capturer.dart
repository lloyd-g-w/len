import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Rect;

import '../../../app_services.dart';
import '../../../data/surface_copier.dart';
import '../../../domain/chunk_grid.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../ink/surface_model.dart';
import '../../documents/export/notebook_exporter.dart';
import '../document/document_layout.dart';
import 'area_image.dart';

/// A captured area: the PNG, its size in pixels, and the area it shows
/// (document or world units).
class CapturedArea {
  const CapturedArea(this.png, {required this.area, required this.width, required this.height});

  final Uint8List png;
  final Rect area;
  final int width;
  final int height;
}

/// Renders areas of a notebook to PNGs ([AreaImage]) from what is stored
/// (ink drawn a moment ago is flushed first), with page backgrounds
/// rendered afresh at the capture's resolution as PNG export does.
class AreaCapturer {
  AreaCapturer(this.services)
    : _copier = SurfaceCopier(services.strokes, elements: services.elements);

  final AppServices services;
  final SurfaceCopier _copier;

  /// [area] (document coordinates) of the [pages] laid out in [layout],
  /// trimmed to the pages it touches (the desk around them is left out);
  /// null if it touches none. [screenScale] is how many device pixels a
  /// unit takes on screen (see [AreaImage.scaleFor]).
  Future<CapturedArea?> pages(
    Rect area, {
    required List<NotebookPage> pages,
    required DocumentLayout layout,
    double screenScale = 0,
  }) async {
    final indices = layout.visiblePages(area);
    if (indices.isEmpty) return null;
    final covered = indices.map((i) => layout.frameOf(i)!).reduce((a, b) => a.expandToInclude(b));
    final trimmed = area.intersect(covered);
    if (trimmed.isEmpty) return null;
    final scale = AreaImage.scaleFor(trimmed.size, screenScale: screenScale);
    SurfaceModel.flushAll(); // Ink drawn a moment ago.
    final exporter = NotebookExporter(services);
    final placed = <CapturePage>[];
    try {
      for (final index in indices) {
        final page = pages[index];
        final elements = _copier.loadAllElements(page.id);
        placed.add(
          CapturePage(
            page,
            layout.frameOf(index)!,
            strokes: _copier.loadAll(page.id),
            elements: elements,
            background: await exporter.rasterBackground(page, elements, scale),
          ),
        );
      }
      return await _encode(
        trimmed,
        () => AreaImage.render(trimmed, scale: scale, pages: placed, images: services.images),
      );
    } finally {
      for (final p in placed) {
        p.background?.dispose();
      }
      await exporter.dispose();
    }
  }

  /// [area] (world coordinates) of infinite canvas [notebook].
  Future<CapturedArea?> canvas(
    Rect area, {
    required Notebook notebook,
    double screenScale = 0,
  }) async {
    if (area.isEmpty) return null;
    final scale = AreaImage.scaleFor(area.size, screenScale: screenScale);
    SurfaceModel.flushAll();
    final range = ChunkGrid.rangeFor(area);
    final id = notebook.id;
    final strokes = services.strokes.loadChunks(id, services.strokes.populatedChunks(id, range));
    final elements = services.elements.loadChunks(id, services.elements.populatedChunks(id, range));
    final exporter = NotebookExporter(services);
    try {
      await exporter.loadImages(elements, scale);
    } finally {
      await exporter.dispose();
    }
    final board = CaptureCanvas(
      paper: notebook.paper,
      paperColor: notebook.paperColor,
      strokes: strokes,
      elements: elements,
    );
    return _encode(
      area,
      () => AreaImage.render(area, scale: scale, board: board, images: services.images),
    );
  }

  Future<CapturedArea> _encode(Rect area, Future<ui.Image> Function() render) async {
    final image = await render();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return CapturedArea(
        data!.buffer.asUint8List(),
        area: area,
        width: image.width,
        height: image.height,
      );
    } finally {
      image.dispose();
    }
  }
}
