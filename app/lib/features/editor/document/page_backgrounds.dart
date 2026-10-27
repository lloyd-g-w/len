import 'dart:ui' as ui;
import 'dart:ui' show Canvas, Rect, Size;

import 'package:flutter/foundation.dart';

import '../../../domain/notebook_page.dart';

/// Supplies rendered images of page backgrounds (e.g. PDF pages).
///
/// Rendering is asynchronous: [imageFor] returns the best image available
/// right now (possibly at a lower resolution, or null) and schedules a
/// render at the requested size; listeners are notified when it is ready.
abstract class PageBackgrounds implements Listenable {
  /// An image of the whole [background], ideally about [pixelWidth] pixels
  /// wide (e.g. for thumbnails).
  ui.Image? imageFor(PageBackground background, double pixelWidth);

  /// Paints [background] over a page of [page] units at the origin of
  /// [canvas], sharp in the [visible] part (page units) at [pixelsPerUnit]
  /// device pixels per unit. Deep zoom may paint only the visible part
  /// sharply (tiles) over a coarser whole page. [rank] says how central
  /// the page is in the view ([centralRanks]): renders of the page at
  /// rank 0 go first; a paint at rank 0 also starts a new frame (what the
  /// previous frame [prefetch]ed and no longer wants is dropped).
  void paint(
    Canvas canvas,
    PageBackground background,
    Size page,
    Rect visible,
    double pixelsPerUnit, {
    int rank = 0,
  });

  /// Asks for [background] (a page of [page] units just outside the view,
  /// [after] the visible ones or before them) to be ready at
  /// [pixelsPerUnit] when it scrolls in: rendered after everything in
  /// view, the side the view is moving to first.
  void prefetch(PageBackground background, Size page, double pixelsPerUnit, {required bool after});

  /// Whether [background]'s file couldn't be had: it is neither on this
  /// device nor could it be fetched (or it could not be read). Such pages
  /// show a placeholder instead of staying silently blank.
  bool isMissing(PageBackground background);

  void dispose();
}

/// How central each of [frames] is in [view]: 0 for the frame nearest its
/// centre (the page being read), 1 for the next nearest, and so on.
List<int> centralRanks(List<Rect> frames, Rect view) {
  final c = view.center;
  double gap(Rect f) {
    final dx = c.dx < f.left ? f.left - c.dx : (c.dx > f.right ? c.dx - f.right : 0.0);
    final dy = c.dy < f.top ? f.top - c.dy : (c.dy > f.bottom ? c.dy - f.bottom : 0.0);
    return dx * dx + dy * dy;
  }

  final order = List.generate(frames.length, (i) => i)
    ..sort((a, b) {
      final byGap = gap(frames[a]).compareTo(gap(frames[b]));
      if (byGap != 0) return byGap;
      return (frames[a].center - c).distanceSquared.compareTo(
        (frames[b].center - c).distanceSquared,
      );
    });
  final ranks = List.filled(frames.length, 0);
  for (var k = 0; k < order.length; k++) {
    ranks[order[k]] = k;
  }
  return ranks;
}
