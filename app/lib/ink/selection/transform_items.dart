import 'dart:math' as math;
import 'dart:ui';

import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../../domain/text_data.dart';
import '../elements/text_layout.dart';
import '../geometry/affine.dart';

/// Applies selection transforms to immutable strokes and elements.
abstract final class TransformItems {
  static const double _minWidth = 0.1;
  static const double _maxWidth = 400;

  /// [stroke] moved by [t], as a new stroke with id [id]. The line width
  /// scales with the transform's mean scale. Paint order ([Stroke.createdAt])
  /// is kept, so moved ink stays above/below what it was above/below.
  static Stroke stroke(Stroke stroke, Affine t, {required String id}) {
    final points = [
      for (final p in stroke.points)
        () {
          final q = t.apply(p.offset);
          return StrokePoint(q.dx, q.dy, p.pressure);
        }(),
    ];
    return Stroke(
      id: id,
      surfaceId: stroke.surfaceId,
      tool: stroke.tool,
      color: stroke.color,
      width: (stroke.width * t.meanScale).clamp(_minWidth, _maxWidth),
      points: points,
      createdAt: stroke.createdAt,
      style: stroke.style,
    );
  }

  /// [element] moved by [t] (same id). The box follows the transform's
  /// rotation and its scale along the element's own axes.
  ///
  /// Text scales its font with uniform scaling (corner handles) and only
  /// rewraps to a new width with one-axis scaling; its height always comes
  /// from layout.
  static SurfaceElement element(SurfaceElement element, Affine t) {
    if (t.isTranslation) {
      return element.copyWith(rect: element.rect.shift(Offset(t.tx, t.ty)));
    }
    final r = element.rotation;
    final u = Offset(math.cos(r), math.sin(r));
    final v = Offset(-math.sin(r), math.cos(r));
    final tu = t.applyVector(u);
    final su = tu.distance;
    final sv = t.applyVector(v).distance;
    final centre = t.apply(element.rect.center);
    final rotation = _normalize(math.atan2(tu.dy, tu.dx));
    var width = element.rect.width * su;
    var height = element.rect.height * sv;
    var data = element.data;
    if (element.knownType == ElementType.text) {
      final text = TextData.fromJson(element.data);
      final uniform = (su - sv).abs() <= 1e-3 * math.max(su, sv);
      final scaled = uniform
          ? text.copyWith(
              fontSize: (text.fontSize * su).clamp(TextData.minFontSize, TextData.maxFontSize),
            )
          : text;
      width = math.max(width, TextLayout.minWidth);
      height = TextLayout.heightOf(scaled, width);
      data = scaled.toJson(element.data);
    }
    return element.copyWith(
      rect: Rect.fromCenter(center: centre, width: width, height: height),
      rotation: rotation,
      data: data,
    );
  }

  /// Rotation in (-π, π]; tiny float residue snaps to 0.
  static double _normalize(double angle) {
    var a = angle % (2 * math.pi);
    if (a > math.pi) a -= 2 * math.pi;
    return a.abs() < 1e-9 ? 0 : a;
  }

  /// [stroke] recoloured (new id), keeping everything else.
  static Stroke recolorStroke(Stroke stroke, int argb, {required String id}) => Stroke(
    id: id,
    surfaceId: stroke.surfaceId,
    tool: stroke.tool,
    color: argb,
    width: stroke.width,
    points: stroke.points,
    createdAt: stroke.createdAt,
    style: stroke.style,
  );

  /// [element] recoloured; types without a colour are returned unchanged.
  static SurfaceElement recolorElement(SurfaceElement element, int argb) {
    if (element.knownType != ElementType.text) return element;
    final text = TextData.fromJson(element.data).copyWith(color: argb);
    return element.copyWith(data: text.toJson(element.data));
  }
}
