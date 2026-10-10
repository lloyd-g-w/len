import 'dart:ui';

/// The payload of an image element (`SurfaceElement.data` of type `image`):
/// the content hash of the image blob, the image's natural size in pixels
/// and an optional crop.
///
/// The crop is a rectangle in *normalised* image coordinates (0..1 on both
/// axes), so it does not depend on the resolution the image is decoded at.
/// The element's box shows exactly the cropped part. Parsing tolerates
/// missing or malformed fields and ignores unknown ones.
class ImageData {
  const ImageData({required this.blob, required this.width, required this.height, Rect? crop})
    : crop = crop ?? full;

  /// SHA-256 (lowercase hex) of the encoded image blob.
  final String blob;

  /// Natural size of the stored image, in pixels (0 when unknown).
  final int width;
  final int height;

  /// Visible part of the image, normalised (see class docs).
  final Rect crop;

  /// The whole image.
  static const Rect full = Rect.fromLTWH(0, 0, 1, 1);

  /// Smallest crop extent (normalised), so a crop never collapses.
  static const double minCrop = 0.02;

  bool get isCropped => crop != full;

  /// Natural size of the visible (cropped) part, in pixels.
  Size get croppedSize => Size(width * crop.width, height * crop.height);

  factory ImageData.fromJson(Map<String, Object?> json) {
    final blob = json['blob'];
    return ImageData(
      blob: blob is String ? blob : '',
      width: _int(json['width']),
      height: _int(json['height']),
      crop: _crop(json['crop']),
    );
  }

  /// Merges into [base] so unknown keys written by newer clients survive
  /// an edit made here. An uncropped image stores no `crop`.
  Map<String, Object?> toJson([Map<String, Object?> base = const {}]) => {
    ...base,
    'blob': blob,
    'width': width,
    'height': height,
    'crop': isCropped ? {'x': crop.left, 'y': crop.top, 'w': crop.width, 'h': crop.height} : null,
  }..removeWhere((key, value) => key == 'crop' && value == null);

  ImageData copyWith({Rect? crop}) =>
      ImageData(blob: blob, width: width, height: height, crop: crop ?? this.crop);

  /// [crop] limited to the image and to at least [minCrop] on each axis.
  static Rect clampCrop(Rect crop) {
    final left = crop.left.clamp(0.0, 1 - minCrop);
    final top = crop.top.clamp(0.0, 1 - minCrop);
    final right = crop.right.clamp(left + minCrop, 1.0);
    final bottom = crop.bottom.clamp(top + minCrop, 1.0);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static int _int(Object? v) => v is num && v.isFinite && v > 0 ? v.round() : 0;

  static Rect _crop(Object? v) {
    if (v is! Map) return full;
    double? n(Object? x) => x is num && x.isFinite ? x.toDouble() : null;
    final x = n(v['x']), y = n(v['y']), w = n(v['w']), h = n(v['h']);
    if (x == null || y == null || w == null || h == null || w <= 0 || h <= 0) return full;
    return normaliseCrop(Rect.fromLTWH(x, y, w, h));
  }

  /// [crop] clamped ([clampCrop]); float noise around the whole image
  /// snaps to [full], so an uncropped image never counts as cropped.
  static Rect normaliseCrop(Rect crop) {
    final r = clampCrop(crop);
    const e = 1e-6;
    final whole = r.left < e && r.top < e && r.right > 1 - e && r.bottom > 1 - e;
    return whole ? full : r;
  }

  @override
  bool operator ==(Object other) =>
      other is ImageData &&
      other.blob == blob &&
      other.width == width &&
      other.height == height &&
      other.crop == crop;

  @override
  int get hashCode => Object.hash(blob, width, height, crop);
}
