import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../domain/paper.dart';
import '../../../domain/stroke.dart';
import '../../../ink/surface_model.dart';
import '../../../ink/tools/content_hit_test.dart';
import '../../../ink/viewport.dart';
import '../../editor/document/document_controller.dart';

/// A surface on screen: its model, where its origin lies in [ReplayTarget]
/// world space, its clip (the page, in surface units) and paper colour.
typedef ReplaySurface = ({SurfaceModel model, Offset origin, Rect? clip, Color paper});

/// What ink replay draws over and hit-tests: the visible surfaces of an
/// infinite canvas or of a paged document, under one viewport.
abstract class ReplayTarget {
  ReplayTarget._();

  /// One infinite canvas.
  factory ReplayTarget.canvas(SurfaceModel model, ViewportController viewport, PaperColor paper) =
      _CanvasTarget;

  /// The visible pages of a paged notebook.
  factory ReplayTarget.document(DocumentController doc) = _DocumentTarget;

  /// Maps the target's world space to the screen.
  ViewportController get viewport;

  /// Notifies when what is shown changes (viewport, loaded chunks, edits).
  Listenable get changes;

  /// The surfaces visible in a view of [size].
  Iterable<ReplaySurface> visible(Size size);

  /// The topmost stroke within [tolerance] screen pixels of [screen].
  Stroke? strokeAt(Offset screen, {double tolerance = 10}) {
    final world = viewport.toWorld(screen);
    final radius = tolerance / viewport.scale;
    for (final s in visible(viewport.size)) {
      final local = world - s.origin;
      if (s.clip != null && !s.clip!.inflate(radius).contains(local)) continue;
      final hit = ContentHitTest.strokeAt(s.model, local, radius);
      if (hit != null) return hit;
    }
    return null;
  }
}

class _CanvasTarget extends ReplayTarget {
  _CanvasTarget(this.model, this.viewport, this.paper) : super._();

  final SurfaceModel model;
  @override
  final ViewportController viewport;
  final PaperColor paper;

  @override
  late final Listenable changes = Listenable.merge([model, viewport]);

  @override
  Iterable<ReplaySurface> visible(Size size) => [
    (model: model, origin: Offset.zero, clip: null, paper: paper.paper),
  ];
}

class _DocumentTarget extends ReplayTarget {
  _DocumentTarget(this.doc) : super._();

  final DocumentController doc;

  @override
  ViewportController get viewport => doc.viewport;

  @override
  late final Listenable changes = Listenable.merge([doc, doc.viewport, doc.surfaces]);

  @override
  Iterable<ReplaySurface> visible(Size size) sync* {
    final layout = doc.layout;
    final pages = doc.pages;
    for (final index in layout.visiblePages(viewport.visibleWorldFor(size))) {
      final surface = doc.surfaces.peek(pages[index].id);
      final frame = layout.frameOf(index);
      if (surface == null || frame == null) continue;
      yield (
        model: surface.model,
        origin: frame.topLeft,
        clip: Offset.zero & frame.size,
        paper: pages[index].paperColor.paper,
      );
    }
  }
}
