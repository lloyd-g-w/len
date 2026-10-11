import 'package:flutter/material.dart';

/// The border of the app's filled text fields: a rounded box (outlined
/// only when [borderSide] is visible, e.g. focused or in error) whose
/// floating label stays *inside* the fill, as in a filled field, rather
/// than sitting on the box's top edge as an [OutlineInputBorder] does.
class FilledFieldBorder extends InputBorder {
  const FilledFieldBorder({super.borderSide = BorderSide.none, required this.borderRadius});

  final BorderRadius borderRadius;

  @override
  bool get isOutline => false;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.width);

  @override
  FilledFieldBorder copyWith({BorderSide? borderSide, BorderRadius? borderRadius}) =>
      FilledFieldBorder(
        borderSide: borderSide ?? this.borderSide,
        borderRadius: borderRadius ?? this.borderRadius,
      );

  @override
  FilledFieldBorder scale(double t) =>
      FilledFieldBorder(borderSide: borderSide.scale(t), borderRadius: borderRadius * t);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.resolve(textDirection).toRRect(rect).deflate(borderSide.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.resolve(textDirection).toRRect(rect));

  @override
  void paintInterior(Canvas canvas, Rect rect, Paint paint, {TextDirection? textDirection}) =>
      canvas.drawRRect(borderRadius.resolve(textDirection).toRRect(rect), paint);

  @override
  bool get preferPaintInterior => true;

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0,
    double gapPercentage = 0,
    TextDirection? textDirection,
  }) {
    if (borderSide.style == BorderStyle.none || borderSide.width == 0) return;
    final rrect = borderRadius.resolve(textDirection).toRRect(rect);
    canvas.drawRRect(rrect.deflate(borderSide.width / 2), borderSide.toPaint());
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is FilledFieldBorder
      ? FilledFieldBorder(
          borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
          borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
        )
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is FilledFieldBorder
      ? FilledFieldBorder(
          borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
          borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
        )
      : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) =>
      other is FilledFieldBorder &&
      other.borderSide == borderSide &&
      other.borderRadius == borderRadius;

  @override
  int get hashCode => Object.hash(borderSide, borderRadius);
}
