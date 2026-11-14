import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// In the JavaScript build, paints one of each common kind of draw the
/// app's screens make beneath [child] for its first frames, so that CanvasKit
/// compiles their GPU programs while the app starts rather than when a
/// screen first shows them (each a GPU round trip on the UI thread: 0.1–1
/// s under software GL). Natively and in WebAssembly (Skwasm renders off
/// the UI thread) it is just [child].
class WebShaderWarmUp extends StatefulWidget {
  const WebShaderWarmUp({super.key, required this.child, @visibleForTesting bool? enabled})
    : enabled = enabled ?? (kIsWeb && !kIsWasm);

  final Widget child;

  /// Whether the warm-up is painted (the JavaScript build).
  final bool enabled;

  @override
  State<WebShaderWarmUp> createState() => _WebShaderWarmUpState();
}

class _WebShaderWarmUpState extends State<WebShaderWarmUp> {
  ui.Image? _image;

  /// The variant painted next ([_WarmUpPainter.variants] when done): one a
  /// frame, so no frame waits for all of their compiles.
  int _variant = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    // A CPU image, like those decoded and rasterised (no read-back).
    final pixels = Uint8List(16 * 16 * 4)..fillRange(0, 16 * 16 * 4, 0x80);
    ui.decodeImageFromPixels(pixels, 16, 16, ui.PixelFormat.rgba8888, (image) {
      if (!mounted) return image.dispose();
      setState(() => _image = image);
      _next();
    });
  }

  /// Moves on to the next variant once a frame has drawn this one.
  void _next() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    setState(() => _variant++);
    if (_variant < _WarmUpPainter.variants) _next();
  });

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    // Beneath the app (opaque: it never shows); the child stays in place
    // when it goes.
    return CustomPaint(
      painter: _variant >= _WarmUpPainter.variants || image == null
          ? null
          : _WarmUpPainter(
              image,
              Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
              _variant,
            ),
      child: widget.child,
    );
  }
}

class _WarmUpPainter extends CustomPainter {
  _WarmUpPainter(this.image, this.text, this.variant);

  final ui.Image image;
  final TextStyle text;

  /// Which of [variants] to paint: on the screen, within a rounded clip
  /// (popovers, dialogs, covers) or on a layer (fades), each needing
  /// programs of its own.
  final int variant;

  static const int variants = 3;

  @override
  void paint(Canvas canvas, Size size) {
    switch (variant) {
      case 0:
        _draw(canvas);
      case 1:
        canvas
          ..save()
          ..clipRRect(RRect.fromLTRBR(0, 0, 90, 90, const Radius.circular(6)));
        _draw(canvas);
        canvas.restore();
      default:
        canvas.saveLayer(
          const Rect.fromLTWH(0, 0, 96, 96),
          Paint()..color = const Color(0x80000000),
        );
        _draw(canvas);
        canvas.restore();
    }
  }

  void _draw(Canvas canvas) {
    final fill = Paint()..color = const Color(0xFF3355AA);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF202020);
    final wide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x99202020);
    final path = Path()
      ..moveTo(4, 4)
      ..cubicTo(30, 0, 50, 40, 80, 10)
      ..lineTo(70, 60)
      ..quadraticBezierTo(40, 80, 6, 30)
      ..close();
    canvas
      ..drawRect(const Rect.fromLTWH(2.5, 2.5, 40, 20), fill)
      ..drawRect(const Rect.fromLTWH(2, 2, 40, 20), fill)
      ..drawRect(const Rect.fromLTWH(2.5, 2.5, 40, 20), line)
      ..drawLine(const Offset(0, 40), const Offset(90, 40), line)
      ..drawRRect(RRect.fromLTRBR(4, 4, 60, 30, const Radius.circular(4)), fill)
      ..drawRRect(RRect.fromLTRBR(4, 4, 60, 30, const Radius.circular(6)), line)
      ..drawRRect(RRect.fromLTRBXY(4, 34, 80, 50, 8, 4), fill)
      ..drawCircle(const Offset(20, 60), 3, fill)
      ..drawCircle(const Offset(40, 60), 12, fill)
      ..drawCircle(const Offset(60, 60), 10, wide)
      ..drawOval(const Rect.fromLTWH(10, 70, 30, 16), fill)
      ..drawArc(const Rect.fromLTWH(50, 50, 30, 30), 0, 2, false, wide)
      ..drawPath(path, fill)
      ..drawPath(path, wide)
      ..drawPath(path, line)
      ..drawImageRect(
        image,
        const Rect.fromLTWH(0, 0, 16, 16),
        const Rect.fromLTWH(10, 10, 40, 40),
        Paint()..filterQuality = FilterQuality.none,
      )
      ..drawImageRect(
        image,
        const Rect.fromLTWH(0, 0, 16, 16),
        const Rect.fromLTWH(10, 10, 40, 40),
        Paint()..filterQuality = FilterQuality.low,
      )
      ..drawImageRect(
        image,
        const Rect.fromLTWH(0, 0, 16, 16),
        const Rect.fromLTWH(10, 10, 8, 8),
        Paint()..filterQuality = FilterQuality.medium,
      )
      ..drawImage(image, const Offset(30, 30), Paint())
      ..drawShadow(
        Path()..addRRect(RRect.fromLTRBR(10, 10, 70, 50, const Radius.circular(6))),
        const Color(0xFF000000),
        3,
        false,
      );
    // The design's shadows (Shadows.low / high): blurred rounded boxes.
    for (final blur in const [1.0, 2.0, 6.0, 24.0]) {
      canvas.drawRRect(
        RRect.fromLTRBR(10, 10, 70, 50, const Radius.circular(4)),
        BoxShadow(color: const Color(0x20000000), blurRadius: blur).toPaint(),
      );
    }
    final painter = TextPainter(
      text: TextSpan(text: 'Len 1', style: text.copyWith(fontSize: 15)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, const Offset(4, 60));
    painter.dispose();
  }

  @override
  bool shouldRepaint(_WarmUpPainter old) => old.variant != variant || old.image != image;
}
