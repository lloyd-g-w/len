import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../../ui/app_theme.dart';

/// Paints what a page shows when its PDF background can't be had (UX_AUDIT
/// #24): a quiet hatched sheet saying so, rather than a blank page that
/// looks as if the PDF were simply empty. [page] is the page's size in page
/// units; the canvas is in page units at its origin.
///
/// The colours are fixed, not themed: PDF pages are white paper in both
/// themes, like the PDF they stand in for.
void paintMissingPdf(Canvas canvas, Size page) {
  final rect = Offset.zero & page;
  canvas
    ..save()
    ..clipRect(rect)
    ..drawRect(rect, Paint()..color = const Color(0xFFF3F3F3));

  // Diagonal hatching, spaced by the page's size so it reads the same on a
  // thumbnail and on screen.
  final step = page.shortestSide / 18;
  final hatch = Paint()
    ..color = const Color(0xFFE4E4E4)
    ..strokeWidth = step / 6;
  for (var x = -page.height; x < page.width; x += step) {
    canvas.drawLine(Offset(x, page.height), Offset(x + page.height, 0), hatch);
  }

  // The message, centred on a plate so the hatching doesn't run through it.
  final size = math.max(page.shortestSide * 0.034, 1.0);
  final text = TextPainter(
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    text: TextSpan(
      style: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: size,
        height: 1.35,
        color: const Color(0xFF5A5A5A),
        fontWeight: FontWeight.w600,
      ),
      children: [
        const TextSpan(text: 'PDF page unavailable\n'),
        TextSpan(
          text: 'Its file isn’t on this device',
          style: TextStyle(fontSize: size * 0.8, fontWeight: FontWeight.w400),
        ),
      ],
    ),
  )..layout(maxWidth: page.width * 0.8);
  final plate = Rect.fromCenter(
    center: rect.center,
    width: text.width + size * 2,
    height: text.height + size * 1.4,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(plate, Radius.circular(size * 0.6)),
    Paint()..color = const Color(0xFFF3F3F3),
  );
  text
    ..paint(canvas, rect.center - Offset(text.width / 2, text.height / 2))
    ..dispose();
  canvas.restore();
}
