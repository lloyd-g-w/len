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
  /// sharply (tiles) over a coarser whole page.
  void paint(
    Canvas canvas,
    PageBackground background,
    Size page,
    Rect visible,
    double pixelsPerUnit,
  );

  /// Whether [background]'s file couldn't be had: it is neither on this
  /// device nor could it be fetched (or it could not be read). Such pages
  /// show a placeholder instead of staying silently blank.
  bool isMissing(PageBackground background);

  void dispose();
}
