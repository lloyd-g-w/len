part of 'text_box_editor.dart';

/// The box's handles and where it sits on screen: resizing by an edge,
/// the round grips, and the world-to-screen transform and bounds.
extension _TextBoxHandles on _TextBoxEditorState {
  /// Drags the left (`side` < 0) or right edge of the box by [d] (along
  /// the box's own axis).
  void _resize(double side, Offset d) {
    final e = _session.current;
    if (e == null) return;
    final rot = e.rotation;
    final along = d.dx * math.cos(rot) + d.dy * math.sin(rot);
    final r = e.rect;
    if (side > 0) {
      _session.setWidth(r.left, r.width + along);
    } else {
      final width = math.max(r.width - along, TextLayout.minWidth);
      _session.setWidth(r.right - width, width);
    }
  }

  /// A round handle on the box edge (constant size on screen) that drags
  /// the box in world units.
  Widget _grip(
    double scale,
    Color accent, {
    required double pad,
    required Alignment alignment,
    required IconData icon,
    required String tooltip,
    required ValueChanged<Offset> onDrag,
  }) {
    final size = 22 / scale;
    Offset? last;
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Transform.translate(
          // Centred on the outline, which is [pad] outside the text.
          offset: Offset(alignment.x * (size / 2 + pad), alignment.y * (size / 2 + pad)),
          child: Tooltip(
            message: tooltip,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => last = _world(d.globalPosition),
              onPanUpdate: (d) {
                final world = _world(d.globalPosition);
                onDrag(world - (last ?? world));
                last = world;
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: Icon(icon, size: 14 / scale, color: Tones.light.onAccent),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// World box → screen: the viewport transform, then the element's
  /// rotation about its centre.
  Matrix4 _matrix(SurfaceElement e) {
    final v = widget.viewport;
    final centre = v.toScreen(e.rect.center);
    return Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..scaleByDouble(v.scale, v.scale, 1, 1)
      ..rotateZ(e.rotation)
      ..translateByDouble(-e.rect.width / 2, -e.rect.height / 2, 0, 1);
  }

  Rect _screenBounds(SurfaceElement e) {
    final v = widget.viewport;
    final pts = e.corners.map(v.toScreen).toList();
    final xs = pts.map((p) => p.dx), ys = pts.map((p) => p.dy);
    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }
}
