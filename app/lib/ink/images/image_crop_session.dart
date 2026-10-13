import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../domain/image_data.dart';
import '../../domain/surface_element.dart';
import '../geometry/affine.dart';
import '../surface_model.dart';
import '../undo_history.dart';

/// The grab points of the crop frame (as fractions of the crop rect).
enum CropHandle {
  topLeft(Offset(0, 0)),
  top(Offset(0.5, 0)),
  topRight(Offset(1, 0)),
  right(Offset(1, 0.5)),
  bottomRight(Offset(1, 1)),
  bottom(Offset(0.5, 1)),
  bottomLeft(Offset(0, 1)),
  left(Offset(0, 0.5));

  const CropHandle(this.fraction);

  final Offset fraction;
}

/// Cropping one image element.
///
/// Works in the element's own, unrotated frame ("local" coordinates: the
/// world rotated back about the element's original centre), where the
/// whole image is the axis-aligned [imageRect] and the crop a rectangle
/// [crop] inside it. While the session runs, the element is hidden from
/// the committed layer and an overlay shows the whole image with the crop.
/// [commit] stores the result as one undoable edit; the visible part of
/// the image stays exactly where it was on the surface.
class ImageCropSession extends ChangeNotifier {
  ImageCropSession({required this.model, required this.element})
    : data = ImageData.fromJson(element.data) {
    final r = element.rect, c = data.crop;
    final w = r.width / c.width, h = r.height / c.height;
    imageRect = Rect.fromLTWH(r.left - c.left * w, r.top - c.top * h, w, h);
    _crop = r;
    model
      ..setHidden({element.id}, owner: this)
      ..addListener(_onModelChanged);
    _imageChanges = model.images?.changes.listen((blob) {
      if (blob == data.blob) notifyListeners();
    });
  }

  final SurfaceModel model;

  /// The element as it was when cropping started.
  final SurfaceElement element;
  final ImageData data;

  /// The whole image in local coordinates.
  late final Rect imageRect;

  late Rect _crop;
  bool _ended = false;
  StreamSubscription<String>? _imageChanges;

  /// Called when the session ends by itself (its element changed).
  VoidCallback? onAbandoned;

  /// The crop in local coordinates.
  Rect get crop => _crop;

  /// The pivot of the local frame (the element's original centre).
  Offset get pivot => element.rect.center;

  /// Local → world.
  Affine get toWorld => Affine.rotation(element.rotation, pivot: pivot);

  /// World → local.
  Affine get toLocal => Affine.rotation(-element.rotation, pivot: pivot);

  /// Smallest crop extent, in local units.
  double get minExtent =>
      math.max(4, ImageData.minCrop * math.max(imageRect.width, imageRect.height));

  /// Moves [handle] to world point [pointer] (clamped to the image).
  void dragHandle(CropHandle handle, Offset pointer) {
    final p = toLocal.apply(pointer);
    var l = _crop.left, t = _crop.top, r = _crop.right, b = _crop.bottom;
    final min = minExtent;
    if (handle.fraction.dx == 0) l = p.dx.clamp(imageRect.left, r - min);
    if (handle.fraction.dx == 1) r = p.dx.clamp(l + min, imageRect.right);
    if (handle.fraction.dy == 0) t = p.dy.clamp(imageRect.top, b - min);
    if (handle.fraction.dy == 1) b = p.dy.clamp(t + min, imageRect.bottom);
    _set(Rect.fromLTRB(l, t, r, b));
  }

  /// Moves the crop window by a world-space [delta], within the image.
  void pan(Rect from, Offset delta) {
    final d = toLocal.applyVector(delta);
    final dx = d.dx.clamp(imageRect.left - from.left, imageRect.right - from.right);
    final dy = d.dy.clamp(imageRect.top - from.top, imageRect.bottom - from.bottom);
    _set(from.shift(Offset(dx, dy)));
  }

  /// Shows the whole image again.
  void reset() => _set(imageRect);

  void _set(Rect crop) {
    if (crop == _crop) return;
    _crop = crop;
    notifyListeners();
  }

  /// The element with the current crop: same id, rotation and position of
  /// what stays visible.
  SurfaceElement get result {
    final normalised = ImageData.normaliseCrop(
      Rect.fromLTWH(
        (_crop.left - imageRect.left) / imageRect.width,
        (_crop.top - imageRect.top) / imageRect.height,
        _crop.width / imageRect.width,
        _crop.height / imageRect.height,
      ),
    );
    final centre = toWorld.apply(_crop.center);
    return element.copyWith(
      rect: Rect.fromCenter(center: centre, width: _crop.width, height: _crop.height),
      data: data.copyWith(crop: normalised).toJson(element.data),
    );
  }

  /// Stores the crop (one undoable edit, nothing if unchanged) and ends
  /// the session. Returns the element as stored.
  SurfaceElement commit() {
    final after = result;
    _end();
    if (after.rect == element.rect && ImageData.fromJson(after.data) == data) return element;
    model.commit(InkEdit(removedElements: [element], addedElements: [after]));
    return after;
  }

  /// Ends the session without changing anything.
  void cancel() => _end();

  void _onModelChanged() {
    if (_ended || identical(model.elementById(element.id), element)) return;
    _end();
    onAbandoned?.call();
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    model
      ..removeListener(_onModelChanged)
      ..setHidden(const {}, owner: this);
  }

  @override
  void dispose() {
    _end();
    unawaited(_imageChanges?.cancel());
    super.dispose();
  }
}
