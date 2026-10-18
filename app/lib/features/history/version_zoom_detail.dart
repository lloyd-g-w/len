part of 'version_surface_view.dart';

/// The sharp part of a large sheet's preview zoomed in (an
/// [InteractiveViewer]'s [TransformationController]): its ink at the zoom's
/// pixels, rendered ([VersionInkImages]) once the zoom has rested for
/// [settle] and drawn over the whole sheet's image (which the zoom only
/// enlarges), so no frame draws the strokes.
class _ZoomDetail {
  _ZoomDetail(this._view);

  final VersionSurfaceViewState _view;

  /// How long a zoom or pan rests before its part is rendered.
  static const settle = Duration(milliseconds: 150);

  /// Zoomed in less than this, the whole sheet's image is sharp enough.
  static const minScale = 1.25;

  TransformationController? _zoom;
  Timer? _timer;
  InkImageKey? _key;

  /// Whether a part being zoomed into is still to come.
  var pending = false;

  void follow(TransformationController? zoom) {
    if (identical(zoom, _zoom)) return;
    _zoom?.removeListener(_changed);
    _zoom = zoom?..addListener(_changed);
  }

  void _changed() {
    pending = true;
    _timer?.cancel();
    _timer = Timer(settle, _ask);
  }

  /// Asks for the image of the part in view, if zoomed in on a sheet
  /// drawn from an image ([VersionSurfaceViewState._inkAt]).
  void _ask() {
    final view = _view;
    final zoom = _zoom;
    final sheet = view._picture.sheet;
    final at = view._paintedAt;
    final m = zoom?.value;
    final scale = m?.getMaxScaleOnAxis() ?? 1;
    if (!view.mounted || m == null || sheet == null || at == null || scale < minScale) {
      return _drop();
    }
    if (view._inkKey == null) return _drop();
    final bounds = Offset.zero & at.size;
    final visible = MatrixUtils.inverseTransformRect(m, bounds).intersect(bounds);
    if (visible.isEmpty) return _drop();
    final unit = sheet.page.width / at.size.width;
    final from = sheet.origin ?? Offset.zero;
    final pixels = scale * at.dpr;
    final key = (
      strokes: sheet.strokes,
      frame: Rect.fromLTWH(
        from.dx + visible.left * unit,
        from.dy + visible.top * unit,
        visible.width * unit,
        visible.height * unit,
      ),
      width: (visible.width * pixels).ceil(),
      height: (visible.height * pixels).ceil(),
    );
    if (key == _key) {
      pending = false;
      return;
    }
    _key = key;
    unawaited(
      view.widget.sheets.inkImages.image(key, wanted: () => view.mounted && _key == key).then((
        image,
      ) {
        if (!view.mounted || _key != key) {
          image?.dispose();
          return;
        }
        pending = false;
        view._picture.showDetail(image == null ? null : (image: image, frame: key.frame));
      }),
    );
  }

  void _drop() {
    pending = false;
    _key = null;
    if (_view.mounted) _view._picture.showDetail(null);
  }

  void dispose() {
    _timer?.cancel();
    _zoom?.removeListener(_changed);
  }
}
