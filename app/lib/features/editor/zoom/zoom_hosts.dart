import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../domain/paper.dart';
import '../../../ink/navigation/viewport_animator.dart';
import '../../../ink/surface_model.dart';
import '../../../ink/viewport.dart';
import '../document/document_controller.dart';
import 'zoom_host.dart';

/// The zoom window in a paged notebook: the frame lies on a page; at the
/// end of the last page a page like it is added.
class DocumentZoomHost extends ZoomHost {
  DocumentZoomHost({
    required this.doc,
    required this.animator,
    required this.chromeInsets,
    required this.addPageAfter,
  });

  final DocumentController doc;

  @override
  final ViewportAnimator animator;

  /// The screen edges chrome (and the box) covers.
  final EdgeInsets Function() chromeInsets;

  /// Adds a page after page [index] (one undo step), or does nothing.
  final void Function(int index) addPageAfter;

  int _indexOf(String id) => doc.pages.indexWhere((p) => p.id == id);

  @override
  String get current => doc.pages[doc.currentPage].id;

  @override
  bool has(String surfaceId) => _indexOf(surfaceId) != -1;

  @override
  Rect? boundsOf(String surfaceId) {
    final index = _indexOf(surfaceId);
    return index == -1 ? null : Offset.zero & doc.pages[index].size;
  }

  @override
  Paper paperOf(String surfaceId) {
    final index = _indexOf(surfaceId);
    return index == -1 ? const Paper(PaperStyle.blank) : doc.pages[index].paper;
  }

  @override
  SurfaceModel acquire(String surfaceId) => doc.surfaces.acquireModel(surfaceId);

  @override
  void release(String surfaceId) => doc.surfaces.releaseModel(surfaceId);

  @override
  ViewportController get main => doc.viewport;

  @override
  EdgeInsets get covered => chromeInsets();

  @override
  Offset? originOf(String surfaceId) {
    final index = _indexOf(surfaceId);
    return index == -1 ? null : doc.layout.frameOf(index)?.topLeft;
  }

  @override
  void activate(String surfaceId) {
    final index = _indexOf(surfaceId);
    if (index != -1) doc.activate(index);
  }

  @override
  bool isActive(String surfaceId) => doc.activePageData.id == surfaceId;

  @override
  String? nextPage(String surfaceId) {
    final index = _indexOf(surfaceId);
    if (index == -1) return null;
    if (index == doc.pages.length - 1) addPageAfter(index);
    return index + 1 < doc.pages.length ? doc.pages[index + 1].id : null;
  }

  @override
  String? surfaceAt(Offset world) {
    final index = doc.layout.pageAt(world) ?? doc.layout.nearestPage(world);
    return index == null ? null : doc.pages[index].id;
  }

  @override
  Listenable get changes => Listenable.merge([doc, doc.viewport]);

  @override
  Listenable get surfaces => doc;
}

/// The zoom window on an infinite canvas: one surface, no edges; a line
/// ends where the view ended when it began.
class CanvasZoomHost extends ZoomHost {
  CanvasZoomHost({
    required this.surfaceId,
    required this.model,
    required this.main,
    required this.animator,
    required this.paper,
    required this.chromeInsets,
  });

  final String surfaceId;
  final SurfaceModel model;

  @override
  final ViewportController main;

  @override
  final ViewportAnimator animator;

  /// The canvas's paper, and the screen edges chrome (and the box) covers.
  final Paper Function() paper;
  final EdgeInsets Function() chromeInsets;

  @override
  String get current => surfaceId;

  @override
  bool has(String id) => id == surfaceId;

  @override
  Rect? boundsOf(String id) => null;

  @override
  Paper paperOf(String id) => paper();

  @override
  SurfaceModel acquire(String id) => model;

  @override
  void release(String id) {}

  @override
  EdgeInsets get covered => chromeInsets();

  @override
  Offset? originOf(String id) => Offset.zero;

  @override
  void activate(String id) {}

  @override
  String? nextPage(String id) => null;

  @override
  Listenable get changes => main;

  /// The one surface stays.
  @override
  Listenable get surfaces => _none;
  static final Listenable _none = Listenable.merge(const []);
}
