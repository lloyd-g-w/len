import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ink/elements/element_renderer.dart';
import '../../../ink/images/image_crop_session.dart';
import '../../../ink/viewport.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';

/// Crop mode for one image: shows the whole image with the kept part
/// highlighted; the frame's handles crop, dragging inside moves the crop
/// window, a tap outside (or Enter / Done) finishes, Esc / Cancel leaves
/// the image as it was.
///
/// Covers the surface and takes every pointer while it is shown.
class ImageCropOverlay extends StatefulWidget {
  const ImageCropOverlay({
    super.key,
    required this.session,
    required this.viewport,
    required this.onDone,
    required this.onCancel,
  });

  final ImageCropSession session;
  final ViewportController viewport;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  /// Pointer slop around a handle (pixels).
  static const double hitRadius = 18;

  @override
  State<ImageCropOverlay> createState() => _ImageCropOverlayState();
}

class _ImageCropOverlayState extends State<ImageCropOverlay> {
  CropHandle? _handle;
  bool _panning = false;
  Rect _panStart = Rect.zero;
  Offset _downWorld = Offset.zero;
  Offset _downScreen = Offset.zero;
  bool _moved = false;

  ImageCropSession get _session => widget.session;
  ViewportController get _viewport => widget.viewport;

  Offset _screenOf(Offset local) => _viewport.toScreen(_session.toWorld.apply(local));

  CropHandle? _handleAt(Offset screen) {
    CropHandle? best;
    var bestDistance = ImageCropOverlay.hitRadius;
    final crop = _session.crop;
    for (final h in CropHandle.values) {
      final local = Offset(
        crop.left + crop.width * h.fraction.dx,
        crop.top + crop.height * h.fraction.dy,
      );
      final d = (_screenOf(local) - screen).distance;
      // Corners win over edges at the same distance.
      final isCorner = h.fraction.dx != 0.5 && h.fraction.dy != 0.5;
      if (d < bestDistance || (isCorner && d <= bestDistance + 2)) {
        best = h;
        bestDistance = d;
      }
    }
    return best;
  }

  void _down(PointerDownEvent e) {
    _downScreen = e.localPosition;
    _downWorld = _viewport.toWorld(e.localPosition);
    _moved = false;
    _handle = _handleAt(e.localPosition);
    _panning = _handle == null && _session.crop.contains(_session.toLocal.apply(_downWorld));
    _panStart = _session.crop;
  }

  void _move(PointerMoveEvent e) {
    if (!_moved && (e.localPosition - _downScreen).distance < 4) return;
    _moved = true;
    final world = _viewport.toWorld(e.localPosition);
    if (_handle != null) {
      _session.dragHandle(_handle!, world);
    } else if (_panning) {
      _session.pan(_panStart, world - _downWorld);
    }
  }

  void _up(PointerUpEvent e) {
    final outside = _handle == null && !_panning;
    _handle = null;
    _panning = false;
    if (!_moved && outside) widget.onDone(); // A tap beside the image.
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): widget.onDone,
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              child: CustomPaint(
                painter: _CropPainter(
                  session: _session,
                  viewport: _viewport,
                  accent: AppTheme.seed, // handles sit on the paper, not the chrome
                  handleFill: Palette.paper,
                  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                ),
              ),
            ),
            ListenableBuilder(
              listenable: Listenable.merge([_session, _viewport]),
              builder: (context, _) => CustomSingleChildLayout(
                delegate: _BarLayout(_frameOnScreen(), MediaQuery.paddingOf(context)),
                child: _CropBar(
                  cropped: _session.crop != _session.imageRect,
                  onReset: _session.reset,
                  onCancel: widget.onCancel,
                  onDone: widget.onDone,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Rect _frameOnScreen() {
    final r = _session.imageRect;
    final pts = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft].map(_screenOf).toList();
    return pts.skip(1).fold(Rect.fromPoints(pts[0], pts[0]), (a, p) {
      return a.expandToInclude(Rect.fromPoints(p, p));
    });
  }
}

class _CropBar extends StatelessWidget {
  const _CropBar({
    required this.cropped,
    required this.onReset,
    required this.onCancel,
    required this.onDone,
  });

  final bool cropped;
  final VoidCallback onReset;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return FloatingPanel(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Show whole image',
            onPressed: cropped ? onReset : null,
            icon: const Icon(Symbols.crop_free_rounded, size: Glyphs.bar),
          ),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          FilledButton(onPressed: onDone, child: const Text('Done')),
        ],
      ),
    );
  }
}

/// Places the bar under the image (above when there is no room), clear
/// of the editor's chrome.
class _BarLayout extends SingleChildLayoutDelegate {
  _BarLayout(this.target, this.chrome);

  final Rect target;

  /// Screen edges covered by the editor's chrome.
  final EdgeInsets chrome;
  static const double gap = 14, margin = 8;

  double get topInset => chrome.top + margin;
  double get bottomInset => chrome.bottom + margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().deflate(const EdgeInsets.all(margin));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final double x = (target.center.dx - child.width / 2).clamp(
      margin,
      math.max(margin, size.width - child.width - margin),
    );
    var y = target.bottom + gap;
    if (y + child.height > size.height - bottomInset) y = target.top - gap - child.height;
    if (y < topInset) y = size.height - bottomInset - child.height;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_BarLayout old) => old.target != target || old.chrome != chrome;
}

class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.session,
    required this.viewport,
    required this.accent,
    required this.handleFill,
    required this.devicePixelRatio,
  }) : super(repaint: Listenable.merge([session, viewport]));

  final ImageCropSession session;
  final ViewportController viewport;
  final Color accent;
  final Color handleFill;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final image = session.imageRect, crop = session.crop;
    final scale = viewport.scale * devicePixelRatio;
    canvas
      ..save()
      ..translate(viewport.offset.dx, viewport.offset.dy)
      ..scale(viewport.scale)
      ..transform(session.toWorld.matrix4);
    final bitmap = session.model.images?.imageFor(session.data, image.width * scale);
    if (bitmap == null) {
      ElementRenderer.paintImagePlaceholder(canvas, image);
    } else {
      final src = Rect.fromLTWH(0, 0, bitmap.width.toDouble(), bitmap.height.toDouble());
      canvas.drawImageRect(bitmap, src, image, Paint()..filterQuality = FilterQuality.medium);
    }
    // Dim what will be cut away.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(image)
        ..addRect(crop),
      Paint()..color = Palette.cropShade,
    );
    canvas.restore();

    final outline = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = Hairline.rule;
    Offset at(double fx, double fy) => viewport.toScreen(
      session.toWorld.apply(Offset(crop.left + crop.width * fx, crop.top + crop.height * fy)),
    );
    canvas.drawPath(Path()..addPolygon([at(0, 0), at(1, 0), at(1, 1), at(0, 1)], true), outline);
    // Rule-of-thirds guides.
    final guide = Paint()
      ..color = Palette.cropGuide
      ..strokeWidth = Hairline.width;
    for (final f in const [1 / 3, 2 / 3]) {
      canvas
        ..drawLine(at(f, 0), at(f, 1), guide)
        ..drawLine(at(0, f), at(1, f), guide);
    }
    final fill = Paint()..color = handleFill;
    for (final h in CropHandle.values) {
      final p = at(h.fraction.dx, h.fraction.dy);
      final r = h.fraction.dx != 0.5 && h.fraction.dy != 0.5 ? 7.0 : 5.5;
      canvas
        ..drawCircle(p, r, fill)
        ..drawCircle(p, r, outline);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.session != session ||
      old.viewport != viewport ||
      old.accent != accent ||
      old.handleFill != handleFill ||
      old.devicePixelRatio != devicePixelRatio;
}
