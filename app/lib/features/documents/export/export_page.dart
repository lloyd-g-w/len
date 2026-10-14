import 'dart:ui' as ui;
import 'dart:ui' show Offset;

import '../../../domain/notebook_page.dart';
import '../../../domain/pdf_page_space.dart';
import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';
import 'vector/pdf_source_reader.dart';

/// A page to export with its ink, elements and (pre-rendered) background.
class ExportPage {
  const ExportPage(
    this.page,
    this.strokes, {
    this.elements = const [],
    this.background,
    this.image,
    this.worldOrigin,
  });

  final NotebookPage page;
  final List<Stroke> strokes;

  /// Set when [page] is the part of an infinite canvas whose top-left is
  /// here (its content already moved to the page): the pattern then runs
  /// from the world's origin, as on the canvas.
  final Offset? worldOrigin;

  /// Text boxes, images and other elements on the page (each beneath or
  /// above the ink, see [SurfaceElement.belowInk]).
  final List<SurfaceElement> elements;

  /// The imported PDF page behind everything, if any.
  final ExportBackground? background;

  /// The blob of the image behind everything (a scan), if any.
  final String? image;
}

/// An imported PDF page to export behind a page's content: copied from
/// [source] as vectors when possible, else embedded as the image [raster]
/// renders.
class ExportBackground {
  const ExportBackground({required this.pageIndex, required this.raster, this.source, this.links});

  /// The parsed source PDF; null when it can only be rasterised.
  final PdfSourceReader? source;

  /// The page of [source] (zero-based).
  final int pageIndex;

  /// Renders the page as an opaque image (the caller's to dispose).
  final Future<ui.Image?> Function() raster;

  /// Reads the page's links (normalised to the page as shown) when it is
  /// embedded as an image; a copied page brings its own.
  final Future<List<PdfLinkArea>> Function()? links;
}
