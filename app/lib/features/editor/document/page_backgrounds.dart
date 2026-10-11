import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../domain/notebook_page.dart';

/// Supplies rendered images of page backgrounds (e.g. PDF pages).
///
/// Rendering is asynchronous: [imageFor] returns the best image available
/// right now (possibly at a lower resolution, or null) and schedules a
/// render at the requested size; listeners are notified when it is ready.
abstract class PageBackgrounds implements Listenable {
  /// An image of [background], ideally about [pixelWidth] pixels wide.
  ui.Image? imageFor(PageBackground background, double pixelWidth);

  void dispose();
}
