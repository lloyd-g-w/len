import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import 'app_theme.dart';

/// [data] as a QR code, [size] square: black modules on white paper with
/// the 4-module quiet zone scanners need, in both themes (like paper, a
/// code is content and never themed).
class QrCodeView extends StatelessWidget {
  const QrCodeView({super.key, required this.data, this.size = 200, this.semanticLabel});

  final String data;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M));
    return Semantics(
      image: true,
      label: semanticLabel,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Radii.xs),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: CustomPaint(painter: _QrPainter(image)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);

  final QrImage image;

  static const int _quiet = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    final module = size.shortestSide / (count + 2 * _quiet);
    final path = Path();
    for (var y = 0; y < count; y++) {
      for (var x = 0; x < count; x++) {
        if (!image.isDark(y, x)) continue;
        path.addRect(Rect.fromLTWH((x + _quiet) * module, (y + _quiet) * module, module, module));
      }
    }
    canvas.drawPath(path, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}
