import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../domain/notebook_page.dart';
import '../../../ink/viewport.dart';
import '../../editor/document/document_controller.dart';

/// Maps a surface's coordinates to the screen: `screen = local * scale + offset`.
typedef SurfaceTransform = ({Offset offset, double scale});

/// What the in-notebook search needs from an editor: where surfaces are
/// on screen, and a way to bring a spot into view. Implemented for paged
/// documents and infinite canvases, so the search UI does not depend on
/// how the editor is built.
abstract interface class EditorSearchHost {
  /// Notifies when the view or the page layout changes.
  Listenable get changes;

  /// Whether the view has been laid out (has a size).
  bool get isReady;

  /// The page with surface id [surfaceId] (null on canvases or if gone).
  NotebookPage? pageOf(String surfaceId);

  /// Where [surfaceId] is drawn on screen; null if it is not laid out.
  SurfaceTransform? transformOf(String surfaceId);

  /// Scrolls (or turns pages) so [local] on [surfaceId] is visible,
  /// keeping clear of the top [topInset] screen pixels.
  void reveal(String surfaceId, Rect local, {double topInset = 0});
}

/// Screen-space panning shared by the hosts: centres [target] (screen) in
/// the free area if it is not already comfortably inside it.
Offset _panToShow(Rect target, Size size, double topInset) {
  final free = Rect.fromLTRB(0, topInset, size.width, size.height).deflate(24);
  if (free.isEmpty) return Offset.zero;
  final inside =
      target.left >= free.left &&
      target.right <= free.right &&
      target.top >= free.top &&
      target.bottom <= free.bottom;
  if (inside) return Offset.zero;
  // Large targets: show their top-left part.
  final anchor = Offset(
    target.width > free.width ? target.left + free.width / 2 : target.center.dx,
    target.height > free.height ? target.top + free.height / 3 : target.center.dy,
  );
  return free.center - anchor;
}

/// [EditorSearchHost] for a paged notebook.
class DocumentSearchHost implements EditorSearchHost {
  DocumentSearchHost(this.doc);

  final DocumentController doc;

  @override
  late final Listenable changes = Listenable.merge([doc, doc.viewport]);

  @override
  bool get isReady => !doc.viewport.size.isEmpty;

  int _indexOf(String surfaceId) => doc.pages.indexWhere((p) => p.id == surfaceId);

  @override
  NotebookPage? pageOf(String surfaceId) {
    final i = _indexOf(surfaceId);
    return i == -1 ? null : doc.pages[i];
  }

  @override
  SurfaceTransform? transformOf(String surfaceId) {
    final i = _indexOf(surfaceId);
    final frame = i == -1 ? null : doc.layout.frameOf(i);
    if (frame == null) return null;
    return (offset: doc.viewport.toScreen(frame.topLeft), scale: doc.viewport.scale);
  }

  @override
  void reveal(String surfaceId, Rect local, {double topInset = 0}) {
    final i = _indexOf(surfaceId);
    if (i == -1) return;
    var frame = doc.layout.frameOf(i);
    final viewport = doc.viewport;
    if (frame == null || !frame.overlaps(viewport.visibleWorld)) {
      doc.goToPage(i); // Off screen (or another page in single-page flow).
      frame = doc.layout.frameOf(i);
      if (frame == null) return;
    }
    final target = local.shift(frame.topLeft);
    final screen = Rect.fromPoints(
      viewport.toScreen(target.topLeft),
      viewport.toScreen(target.bottomRight),
    );
    viewport.panBy(_panToShow(screen, viewport.size, topInset));
  }
}

/// [EditorSearchHost] for an infinite canvas (a single surface).
class CanvasSearchHost implements EditorSearchHost {
  CanvasSearchHost(this.viewport, {required this.surfaceId});

  final ViewportController viewport;
  final String surfaceId;

  @override
  Listenable get changes => viewport;

  @override
  bool get isReady => !viewport.size.isEmpty;

  @override
  NotebookPage? pageOf(String surfaceId) => null;

  @override
  SurfaceTransform? transformOf(String surfaceId) =>
      surfaceId == this.surfaceId ? (offset: viewport.offset, scale: viewport.scale) : null;

  @override
  void reveal(String surfaceId, Rect local, {double topInset = 0}) {
    if (surfaceId != this.surfaceId || viewport.size.isEmpty) return;
    final size = viewport.size;
    // Zoom out if the box would not fit; never zoom in.
    final room = Size(size.width - 96, size.height - topInset - 96);
    if (local.width * viewport.scale > room.width || local.height * viewport.scale > room.height) {
      final fit = viewport.viewFitting(local, padding: 48, scaleCap: viewport.scale);
      viewport.setView(scale: fit.scale, offset: fit.offset);
    }
    final screen = Rect.fromPoints(
      viewport.toScreen(local.topLeft),
      viewport.toScreen(local.bottomRight),
    );
    viewport.panBy(_panToShow(screen, size, topInset));
  }
}
