import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Lays out a [SegmentedButton] in a row when it fits the room it has, and
/// stacks its segments when it doesn't (narrow phones, large text), so the
/// segments keep their full text size and 48-dp targets. [builder] builds
/// the button for a direction.
class FitSegments extends StatefulWidget {
  const FitSegments({super.key, required this.builder});

  final Widget Function(Axis direction) builder;

  @override
  State<FitSegments> createState() => _FitSegmentsState();
}

class _FitSegmentsState extends State<FitSegments> {
  /// The layout shown; the other one can't take keyboard focus.
  Axis _shown = Axis.horizontal;

  /// Called from layout: catches the focus up a frame later.
  void _picked(Axis axis) {
    if (axis == _shown) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _shown != axis) setState(() => _shown = axis);
    });
  }

  @override
  Widget build(BuildContext context) => _PickAxis(
    onPicked: _picked,
    children: [
      for (final axis in Axis.values)
        ExcludeFocus(excluding: axis != _shown, child: widget.builder(axis)),
    ],
  );
}

/// Shows its first child (a row) if its natural width fits, else its
/// second (a column). Only the shown child paints, hits and has semantics.
class _PickAxis extends MultiChildRenderObjectWidget {
  const _PickAxis({required this.onPicked, required super.children});

  final ValueChanged<Axis> onPicked;

  @override
  MultiChildRenderObjectElement createElement() => _PickAxisElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPickAxis(onPicked);

  @override
  void updateRenderObject(BuildContext context, _RenderPickAxis renderObject) =>
      renderObject.onPicked = onPicked;
}

/// Finders (and the inspector) see only the shown child, as with
/// [Offstage].
class _PickAxisElement extends MultiChildRenderObjectElement {
  _PickAxisElement(super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    final shown = (renderObject as _RenderPickAxis)._shown;
    children.where((c) => shown == null || c.renderObject == shown).forEach(visitor);
  }
}

class _PickParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderPickAxis extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PickParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PickParentData> {
  _RenderPickAxis(this.onPicked);

  ValueChanged<Axis> onPicked;

  RenderBox get _row => firstChild!;
  RenderBox get _column => lastChild!;

  bool _fits(double width) => _row.getMaxIntrinsicWidth(double.infinity) <= width;

  RenderBox _pick(double width) => _fits(width) ? _row : _column;

  RenderBox? _shown;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PickParentData) child.parentData = _PickParentData();
  }

  @override
  double computeMinIntrinsicWidth(double height) => _column.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) => _row.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) => _pick(width).getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _pick(width).getMaxIntrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_pick(constraints.maxWidth).getDryLayout(constraints.loosen()));

  @override
  void performLayout() {
    final shown = _shown = _pick(constraints.maxWidth);
    final hidden = shown == _row ? _column : _row;
    shown.layout(constraints.loosen(), parentUsesSize: true);
    hidden.layout(const BoxConstraints());
    size = constraints.constrain(shown.size);
    onPicked(shown == _row ? Axis.horizontal : Axis.vertical);
  }

  @override
  void paint(PaintingContext context, Offset offset) => context.paintChild(_shown!, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _shown!.hitTest(result, position: position);

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) => visitor(_shown!);
}
