import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import 'page_snapshot.dart';

/// The eyedropper's loupe: the page around the point enlarged (from the
/// [snapshot], pixels kept sharp), a crosshair on the point, and below it
/// a band in the [colour] a pick there takes. Like the scan corner
/// editor's loupe, it sits in a top corner away from the point.
class EyedropperLoupe extends StatelessWidget {
  const EyedropperLoupe({super.key, required this.snapshot, required this.at, this.colour});

  final PageSnapshot? snapshot;

  /// The point (global).
  final Offset at;

  /// The colour picked there; null while it is being read.
  final int? colour;

  /// Side of the enlarged view.
  static const double size = 112;

  /// Height of the colour band.
  static const double band = Gaps.xl;

  /// Magnification over the page as shown.
  static const double zoom = 4;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const ValueKey('eyedropper-loupe'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.md),
        boxShadow: Shadows.low(scheme.brightness),
      ),
      child: CustomPaint(
        size: const Size(size, size + band),
        painter: _LoupePainter(
          snapshot: snapshot,
          at: at,
          colour: colour,
          backdrop: Surfaces.canvasBackdrop(scheme.brightness),
          edge: Surfaces.border(scheme)?.color ?? scheme.outlineVariant,
        ),
      ),
    );
  }
}

class _LoupePainter extends CustomPainter {
  _LoupePainter({
    required this.snapshot,
    required this.at,
    required this.colour,
    required this.backdrop,
    required this.edge,
  });

  final PageSnapshot? snapshot;
  final Offset at;
  final int? colour;
  final Color backdrop;
  final Color edge;

  // On the page, not the chrome: the accent, fixed (as the scan loupe's).
  static const Color _accent = AppTheme.seed;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(Radii.md));
    final view = Rect.fromLTWH(0, 0, size.width, EyedropperLoupe.size);
    canvas
      ..save()
      ..clipRRect(shape)
      ..drawRect(Offset.zero & size, Paint()..color = backdrop);
    if (snapshot case final shot?) {
      // Device pixels around the point, as many as the view holds enlarged.
      final extent = EyedropperLoupe.size / EyedropperLoupe.zoom * shot.dpr;
      final source = Rect.fromCenter(center: shot.toImage(at), width: extent, height: extent);
      canvas.drawImageRect(shot.image, source, view, Paint()..filterQuality = FilterQuality.none);
    }
    final band = Rect.fromLTRB(0, view.bottom, size.width, size.height);
    canvas
      ..drawRect(band, Paint()..color = Color(colour ?? backdrop.toARGB32()))
      ..drawLine(band.topLeft, band.topRight, Paint()..color = edge)
      ..restore();
    // A crosshair with a gap: the picked spot itself stays visible.
    final cross = Paint()
      ..color = _accent
      ..strokeWidth = Hairline.width;
    final c = view.center;
    const gap = Gaps.xs, arm = Gaps.md;
    for (final d in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
      canvas.drawLine(c + d * gap, c + d * (gap + arm), cross);
    }
    canvas.drawRRect(
      shape,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = Hairline.width,
    );
  }

  @override
  bool shouldRepaint(_LoupePainter old) =>
      old.snapshot != snapshot ||
      old.at != at ||
      old.colour != colour ||
      old.backdrop != backdrop ||
      old.edge != edge;
}
