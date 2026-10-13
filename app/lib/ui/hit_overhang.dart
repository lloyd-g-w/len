import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Lets a control's hit area hang over its neighbours without moving them:
/// [child] (a button padded to its touch target, say) is laid out
/// [overhang] larger than the space this widget takes, and painted over
/// that margin. A quiet button keeps its 40-dp plate in a 40-dp header
/// while a finger gets the full 48 dp, and a sheet's ✕ keeps its glyph on
/// the content edge with its padding hanging into the sheet's margin.
///
/// Flutter only hit-tests a box inside its parent's bounds, so taps on the
/// overhang reach [child] through the [HitOverhangScope] above the app.
/// They count only when nothing else is there: when the deepest thing hit
/// is a surface the control sits on (a sheet's margin, the gap above a
/// header), never another control or a route over it.
class HitOverhang extends SingleChildRenderObjectWidget {
  const HitOverhang({super.key, required this.overhang, required Widget super.child});

  /// How far [child] reaches past this widget's box on each side.
  final EdgeInsetsGeometry overhang;

  @override
  RenderHitOverhang createRenderObject(BuildContext context) =>
      RenderHitOverhang(overhang.resolve(Directionality.of(context)));

  @override
  void updateRenderObject(BuildContext context, RenderHitOverhang renderObject) {
    renderObject.overhang = overhang.resolve(Directionality.of(context));
  }
}

/// Routes taps on [HitOverhang]s' overhangs to them; one above the app
/// (`MaterialApp.builder`) covers every route, popover and sheet.
class HitOverhangScope extends SingleChildRenderObjectWidget {
  const HitOverhangScope({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHitOverhangScope();
}

/// The render object of [HitOverhang].
class RenderHitOverhang extends RenderProxyBox {
  RenderHitOverhang(this._overhang);

  EdgeInsets _overhang;
  EdgeInsets get overhang => _overhang;
  set overhang(EdgeInsets value) {
    if (value == _overhang) return;
    _overhang = value;
    markNeedsLayout();
  }

  _RenderHitOverhangScope? _scope;

  /// Where the child lies, in this box's coordinates.
  Rect get _childRect => Rect.fromLTWH(
    -_overhang.left,
    -_overhang.top,
    size.width + _overhang.horizontal,
    size.height + _overhang.vertical,
  );

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    RenderObject? node = parent;
    while (node != null && node is! _RenderHitOverhangScope) {
      node = node.parent;
    }
    _scope = (node as _RenderHitOverhangScope?)?.._overhangs.add(this);
  }

  @override
  void detach() {
    _scope?._overhangs.remove(this);
    _scope = null;
    super.detach();
  }

  /// [constraints], loosened, grown by the overhang: the child's room.
  BoxConstraints _inflate(BoxConstraints constraints) => BoxConstraints(
    maxWidth: constraints.maxWidth + _overhang.horizontal,
    maxHeight: constraints.maxHeight + _overhang.vertical,
  );

  @override
  void performLayout() {
    final child = this.child!;
    child.layout(_inflate(constraints), parentUsesSize: true);
    size = constraints.constrain(_overhang.deflateSize(child.size));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_overhang.deflateSize(child!.getDryLayout(_inflate(constraints))));

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    0,
    super.computeMinIntrinsicWidth(height + _overhang.vertical) - _overhang.horizontal,
  );

  @override
  double computeMaxIntrinsicWidth(double height) => math.max(
    0,
    super.computeMaxIntrinsicWidth(height + _overhang.vertical) - _overhang.horizontal,
  );

  @override
  double computeMinIntrinsicHeight(double width) => math.max(
    0,
    super.computeMinIntrinsicHeight(width + _overhang.horizontal) - _overhang.vertical,
  );

  @override
  double computeMaxIntrinsicHeight(double width) => math.max(
    0,
    super.computeMaxIntrinsicHeight(width + _overhang.horizontal) - _overhang.vertical,
  );

  @override
  void paint(PaintingContext context, Offset offset) =>
      context.paintChild(child!, offset + _childRect.topLeft);

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(_childRect.left, _childRect.top, 0, 1);

  @override
  Rect get paintBounds => _childRect;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _hitChild(result, position);

  bool _hitChild(BoxHitTestResult result, Offset position) => result.addWithPaintOffset(
    offset: _childRect.topLeft,
    position: position,
    hitTest: (result, transformed) => child!.hitTest(result, position: transformed),
  );

  /// Whether [position] (this box's coordinates) is on the overhang and,
  /// seen from [deepest] (the deepest thing a normal hit test found), the
  /// overhang shows there: [deepest] is a surface this control sits on and
  /// no clip between them hides the point.
  bool _claims(Offset position, HitTestTarget deepest) {
    if (!_childRect.contains(position) || (Offset.zero & size).contains(position)) return false;
    RenderObject node = this;
    var point = position;
    for (var parent = node.parent; parent != null; parent = parent.parent) {
      final transform = Matrix4.identity();
      parent.applyPaintTransform(node, transform);
      point = MatrixUtils.transformPoint(transform, point);
      final clip = parent.describeApproximatePaintClip(node);
      if (clip != null && !clip.contains(point)) return false;
      if (identical(parent, deepest)) return true;
      if (parent is _RenderHitOverhangScope) return false;
      node = parent;
    }
    return false;
  }
}

class _RenderHitOverhangScope extends RenderProxyBox {
  final Set<RenderHitOverhang> _overhangs = {};

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_overhangs.isEmpty) return super.hitTest(result, position: position);
    // What a tap here would hit anyway; an overhang only takes the empty
    // surface under it.
    final probe = BoxHitTestResult();
    super.hitTest(probe, position: position);
    final deepest = probe.path.isEmpty ? null : probe.path.first.target;
    var hit = false;
    if (deepest != null) {
      for (final overhang in _overhangs.toList().reversed) {
        if (!overhang.attached || !overhang.hasSize) continue;
        final toScope = overhang.getTransformTo(this);
        final local = MatrixUtils.transformPoint(Matrix4.inverted(toScope), position);
        if (!overhang._claims(local, deepest)) continue;
        // Entered first so the control is first in the gesture arena, as
        // if the tap had landed on it.
        hit = result.addWithPaintTransform(
          transform: toScope,
          position: position,
          hitTest: overhang._hitChild,
        );
        break;
      }
    }
    return super.hitTest(result, position: position) || hit;
  }
}
