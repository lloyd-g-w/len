import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

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
  /// keeping clear of the screen edges in [clear].
  void reveal(String surfaceId, Rect local, {EdgeInsets clear = EdgeInsets.zero});

  /// Drops the extra scroll room [reveal] made to show a match below the
  /// search bar (the bar closed).
  void releaseRoom();
}

/// Screen-space panning shared by the hosts: centres [target] (screen) in
/// the free area along each axis where it is not already comfortably
/// inside it. An axis that already shows the target never moves, so
/// stepping down a page fitted to the width never pans it sideways.
@visibleForTesting
Offset panToShow(Rect target, Size size, EdgeInsets clear) {
  final free = clear.deflateRect(Offset.zero & size).deflate(24);
  if (free.isEmpty) return Offset.zero;
  final insideX = target.left >= free.left && target.right <= free.right;
  final insideY = target.top >= free.top && target.bottom <= free.bottom;
  // Large targets: show their top-left part.
  final dx = insideX
      ? 0.0
      : free.center.dx -
            (target.width > free.width ? target.left + free.width / 2 : target.center.dx);
  final dy = insideY
      ? 0.0
      : free.center.dy -
            (target.height > free.height ? target.top + free.height / 3 : target.center.dy);
  return Offset(dx, dy);
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
  void reveal(String surfaceId, Rect local, {EdgeInsets clear = EdgeInsets.zero}) {
    final i = _indexOf(surfaceId);
    if (i == -1) return;
    doc.beforeJump?.call(); // Stop any glide or page scroll.
    doc.scroller.stop();
    // Room to scroll a match at the very top of a page below the bar.
    doc.setOverlayTop(clear.top);
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
    viewport.panBy(panToShow(screen, viewport.size, clear));
  }

  @override
  void releaseRoom() => doc.setOverlayTop(0);
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
  void reveal(String surfaceId, Rect local, {EdgeInsets clear = EdgeInsets.zero}) {
    if (surfaceId != this.surfaceId || viewport.size.isEmpty) return;
    final size = viewport.size;
    // Zoom out if the box would not fit; never zoom in.
    final room = Size(size.width - clear.horizontal - 96, size.height - clear.vertical - 96);
    if (local.width * viewport.scale > room.width || local.height * viewport.scale > room.height) {
      final fit = viewport.viewFitting(local, padding: 48, scaleCap: viewport.scale);
      viewport.setView(scale: fit.scale, offset: fit.offset);
    }
    final screen = Rect.fromPoints(
      viewport.toScreen(local.topLeft),
      viewport.toScreen(local.bottomRight),
    );
    viewport.panBy(panToShow(screen, size, clear));
  }

  @override
  void releaseRoom() {} // Canvases are unbounded.
}
