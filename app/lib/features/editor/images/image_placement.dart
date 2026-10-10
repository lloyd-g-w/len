import 'dart:math' as math;
import 'dart:ui';

import '../../../domain/image_data.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/elements/element_order.dart';
import '../../../ink/surface_model.dart';
import '../../../ink/undo_history.dart';

/// Where and how large a newly inserted image appears.
abstract final class ImagePlacement {
  /// Share of the visible area (each axis) a new image may cover at most.
  static const double maxShare = 0.7;

  /// The world box for an image of [data] centred on [at]: its natural
  /// size (one pixel per world unit), shrunk to fit [maxShare] of [area],
  /// and kept inside [page] when given.
  static Rect boxFor(ImageData data, {required Offset at, required Rect area, Rect? page}) {
    final natural = data.croppedSize;
    final w = math.max(1.0, natural.width), h = math.max(1.0, natural.height);
    final fit = page == null ? area : area.intersect(page);
    final scale = [
      1.0,
      if (fit.width > 0) fit.width * maxShare / w,
      if (fit.height > 0) fit.height * maxShare / h,
    ].reduce(math.min);
    var box = Rect.fromCenter(center: at, width: w * scale, height: h * scale);
    if (page != null) box = _keepInside(box, page);
    return box;
  }

  static Rect _keepInside(Rect box, Rect page) {
    double shift(double lo, double hi, double min, double max) {
      if (hi - lo > max - min) return (min + max) / 2 - (lo + hi) / 2;
      if (lo < min) return min - lo;
      if (hi > max) return max - hi;
      return 0;
    }

    return box.shift(
      Offset(
        shift(box.left, box.right, page.left, page.right),
        shift(box.top, box.bottom, page.top, page.bottom),
      ),
    );
  }

  /// Adds an image element for [data] to [model] at [box] (one undoable
  /// edit), on top of the layer beneath the ink, and returns it.
  static SurfaceElement insert(
    SurfaceModel model,
    ImageData data,
    Rect box, {
    required String id,
    required int now,
  }) {
    final element = SurfaceElement(
      id: id,
      surfaceId: model.surfaceId,
      type: ElementType.image.name,
      rect: box,
      z: ElementOrder.onTopBelowInk(model.topBelowInkZ),
      createdAt: now,
      data: data.toJson(),
    );
    model.commit(InkEdit(addedElements: [element]));
    return element;
  }
}
