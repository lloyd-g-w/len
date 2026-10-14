import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../domain/paper.dart';
import '../../../domain/paper_pattern.dart';
import '../../../ink/navigation/viewport_animator.dart';
import '../../../ink/surface_model.dart';
import '../../../ink/viewport.dart';

/// What the zoom window needs of the editor it writes in: the surfaces
/// (pages, or the one canvas), how the main view shows them, and moving
/// that view along with the frame. Surfaces are named by id (pages may be
/// added, moved or deleted while the window is open).
abstract class ZoomHost {
  /// The surface the frame starts on (the page in view, or the canvas).
  String get current;

  /// Whether [surfaceId] still exists.
  bool has(String surfaceId);

  /// A page's bounds in its own coordinates; null on a canvas.
  Rect? boundsOf(String surfaceId);

  /// The ruling or grid pitch of the paper, if it has lines to write on.
  double? pitchOf(String surfaceId) {
    final paper = paperOf(surfaceId);
    return switch (paper.style.pitchKind) {
      PitchKind.lines || PitchKind.grid => paper.pitch,
      _ => null,
    };
  }

  /// The paper of [surfaceId].
  Paper paperOf(String surfaceId);

  /// Holds the model of [surfaceId] until [release].
  SurfaceModel acquire(String surfaceId);
  void release(String surfaceId);

  /// The main view (pans and zooms the editor).
  ViewportController get main;

  /// Animates the main view.
  ViewportAnimator get animator;

  /// Screen edges of the main view covered by chrome (and the box).
  EdgeInsets get covered;

  /// Where [surfaceId]'s origin lies in the main view's world, or null
  /// when the view doesn't lay it out (another page in single-page flow).
  Offset? originOf(String surfaceId);

  /// Makes [surfaceId] the surface the editor's own tools work on (the
  /// active page), so its live ink shows on the right page.
  void activate(String surfaceId);

  /// Whether the editor's own input works on [surfaceId] now (its live
  /// ink belongs there).
  bool isActive(String surfaceId) => true;

  /// The page after [surfaceId], added when it is the last; null on a
  /// canvas (or when no page can be added).
  String? nextPage(String surfaceId);

  /// The surface under [world] (main-view coordinates), if another than
  /// the frame's may be (pages).
  String? surfaceAt(Offset world) => null;

  /// What notifies when the main view or the surfaces change.
  Listenable get changes;

  /// The main view's world rectangle not covered by chrome, in
  /// [surfaceId]'s coordinates (null when it isn't laid out).
  Rect? freeArea(String surfaceId) {
    final origin = originOf(surfaceId);
    if (origin == null) return null;
    final screen = covered.deflateRect(Offset.zero & main.size);
    if (screen.isEmpty) return null;
    return Rect.fromPoints(
      main.toWorld(screen.topLeft),
      main.toWorld(screen.bottomRight),
    ).shift(-origin);
  }

  /// [local] on [surfaceId] in main-view screen coordinates.
  Rect? onScreen(String surfaceId, Rect local) {
    final origin = originOf(surfaceId);
    if (origin == null) return null;
    final shifted = local.shift(origin);
    return Rect.fromPoints(main.toScreen(shifted.topLeft), main.toScreen(shifted.bottomRight));
  }

  /// Scrolls the main view (keeping its zoom) just far enough that [local]
  /// on [surfaceId] shows clear of the chrome, [margin] pixels in; centred
  /// along an axis it is too large for.
  void reveal(String surfaceId, Rect local, {double margin = 24}) {
    final screen = onScreen(surfaceId, local);
    if (screen == null) return;
    final free = covered.deflateRect(Offset.zero & main.size).deflate(margin);
    if (free.isEmpty) return;
    double shift(double start, double end, double freeStart, double freeEnd) {
      if (end - start > freeEnd - freeStart) return (freeStart + freeEnd - start - end) / 2;
      if (start < freeStart) return freeStart - start;
      if (end > freeEnd) return freeEnd - end;
      return 0;
    }

    final delta = Offset(
      shift(screen.left, screen.right, free.left, free.right),
      shift(screen.top, screen.bottom, free.top, free.bottom),
    );
    if (delta.distance < 0.5) return;
    animator.animateTo(scale: main.scale, offset: main.offset + delta);
  }

  /// Where the margin rule of [surfaceId]'s paper runs (surface x), if it
  /// has one: lines written through the window start there.
  double? marginOf(String surfaceId) {
    final page = boundsOf(surfaceId);
    if (page == null) return null;
    for (final line in PaperPattern.of(paperOf(surfaceId), page, page: page).lines) {
      if (line.weight == PatternWeight.margin && line.a.dx == line.b.dx) return line.a.dx;
    }
    return null;
  }

  /// The width of the main view's world (surface units), for sizing the
  /// frame on a canvas.
  double get viewWidth => main.size.width / main.scale;
}
