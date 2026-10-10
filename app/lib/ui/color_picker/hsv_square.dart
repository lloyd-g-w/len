import 'package:flutter/material.dart';

/// A saturation (x) / value (y) pad for one hue, with a draggable thumb.
class HsvSquare extends StatelessWidget {
  const HsvSquare({super.key, required this.hsv, required this.onChanged, this.height = 168});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  final double height;

  void _update(Offset local, Size size) {
    final s = (local.dx / size.width).clamp(0.0, 1.0);
    final v = 1 - (local.dy / size.height).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(s).withValue(v));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (d) => _update(d.localPosition, size),
            onPanUpdate: (d) => _update(d.localPosition, size),
            child: Semantics(
              label: 'Saturation and brightness',
              child: CustomPaint(size: size, painter: _SquarePainter(hsv)),
            ),
          );
        },
      ),
    );
  }
}

class _SquarePainter extends CustomPainter {
  _SquarePainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    final pure = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas
      ..save()
      ..clipRRect(rrect)
      ..drawRect(
        rect,
        Paint()..shader = LinearGradient(colors: [Colors.white, pure]).createShader(rect),
      )
      ..drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0xFF000000)],
          ).createShader(rect),
      )
      ..restore();

    final thumb = Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height);
    final fill = hsv.withAlpha(1).toColor();
    canvas
      ..drawCircle(thumb, 11, Paint()..color = const Color(0x33000000))
      ..drawCircle(thumb, 10, Paint()..color = Colors.white)
      ..drawCircle(thumb, 7.5, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_SquarePainter old) => old.hsv != hsv;
}
