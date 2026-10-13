import 'package:flutter/material.dart';

/// The border of the app's text fields (DESIGN §6, "fields are rulings"):
/// a faint fill with [borderRadius] on its top corners and a rule along its
/// bottom edge, drawn in [borderSide] (a 1-dp Pencil rule; 2-dp ruling blue
/// when focused). The floating label stays inside the fill, as in a filled
/// field.
class RuledFieldBorder extends InputBorder {
  const RuledFieldBorder({super.borderSide = BorderSide.none, required this.borderRadius});

  /// The radius of the fill's top corners (the bottom ones are square, on
  /// the rule).
  final Radius borderRadius;

  RRect _box(Rect rect) =>
      RRect.fromRectAndCorners(rect, topLeft: borderRadius, topRight: borderRadius);

  @override
  bool get isOutline => false;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.only(bottom: borderSide.width);

  @override
  RuledFieldBorder copyWith({BorderSide? borderSide, Radius? borderRadius}) => RuledFieldBorder(
    borderSide: borderSide ?? this.borderSide,
    borderRadius: borderRadius ?? this.borderRadius,
  );

  @override
  RuledFieldBorder scale(double t) =>
      RuledFieldBorder(borderSide: borderSide.scale(t), borderRadius: borderRadius * t);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()
        ..addRect(Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom - borderSide.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(_box(rect));

  @override
  void paintInterior(Canvas canvas, Rect rect, Paint paint, {TextDirection? textDirection}) =>
      canvas.drawRRect(_box(rect), paint);

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
    canvas.drawRect(
      Rect.fromLTRB(rect.left, rect.bottom - borderSide.width, rect.right, rect.bottom),
      Paint()..color = borderSide.color,
    );
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is RuledFieldBorder
      ? RuledFieldBorder(
          borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
          borderRadius: Radius.lerp(a.borderRadius, borderRadius, t)!,
        )
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is RuledFieldBorder
      ? RuledFieldBorder(
          borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
          borderRadius: Radius.lerp(borderRadius, b.borderRadius, t)!,
        )
      : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) =>
      other is RuledFieldBorder &&
      other.borderSide == borderSide &&
      other.borderRadius == borderRadius;

  @override
  int get hashCode => Object.hash(borderSide, borderRadius);
}
