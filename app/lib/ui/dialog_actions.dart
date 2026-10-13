import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'app_theme.dart';

/// A dialog's buttons, Cancel first and the primary last: a row aligned to
/// the end when they fit, otherwise a stack of full-width buttons with the
/// primary on top and Cancel at the bottom (each at least [Targets.touch]
/// tall). Unlike an [OverflowBar] it never leaves stacked buttons at their
/// own, ragged widths. It reports intrinsic sizes, so it works inside
/// dialogs that size to their content.
class DialogActions extends MultiChildRenderObjectWidget {
  const DialogActions({super.key, required super.children});

  /// Space between buttons in a row.
  static const double rowSpacing = Gaps.sm;

  /// Space between stacked buttons.
  static const double stackSpacing = Gaps.xs;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderDialogActions(textDirection: Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderDialogActions renderObject) =>
      renderObject.textDirection = Directionality.of(context);
}

class _ActionsParentData extends ContainerBoxParentData<RenderBox> {}

/// The render object of [DialogActions].
class RenderDialogActions extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ActionsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ActionsParentData> {
  RenderDialogActions({required TextDirection textDirection})
    : _textDirection = textDirection; // ignore: prefer_initializing_formals

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  /// Whether the buttons were stacked in the last layout.
  bool get stacked => _stacked;
  bool _stacked = false;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ActionsParentData) child.parentData = _ActionsParentData();
  }

  List<RenderBox> get _children => getChildrenAsList();

  double _rowWidth() {
    final kids = _children;
    if (kids.isEmpty) return 0;
    return kids.fold<double>(0, (sum, c) => sum + c.getMaxIntrinsicWidth(double.infinity)) +
        DialogActions.rowSpacing * (kids.length - 1);
  }

  bool _fitsRow(double width) => _rowWidth() <= width + precisionErrorTolerance;

  @override
  double computeMinIntrinsicWidth(double height) =>
      _children.fold(0, (w, c) => math.max(w, c.getMinIntrinsicWidth(double.infinity)));

  @override
  double computeMaxIntrinsicWidth(double height) => _rowWidth();

  @override
  double computeMinIntrinsicHeight(double width) => _height(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _height(width);

  double _height(double width) {
    final kids = _children;
    if (kids.isEmpty) return 0;
    if (_fitsRow(width)) {
      return kids.fold(0, (h, c) => math.max(h, c.getMaxIntrinsicHeight(double.infinity)));
    }
    return kids.fold<double>(
          0,
          (h, c) => h + math.max(Targets.touch, c.getMaxIntrinsicHeight(width)),
        ) +
        DialogActions.stackSpacing * (kids.length - 1);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = constraints.maxWidth.isFinite ? constraints.maxWidth : _rowWidth();
    return constraints.constrain(Size(_fitsRow(width) ? _rowWidth() : width, _height(width)));
  }

  @override
  void performLayout() {
    final kids = _children;
    if (kids.isEmpty) {
      size = constraints.smallest;
      return;
    }
    final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : _rowWidth();
    _stacked = !_fitsRow(maxWidth);
    if (_stacked) {
      // Primary (last) on top, Cancel (first) at the bottom.
      var y = 0.0;
      for (final child in kids.reversed) {
        child.layout(
          BoxConstraints(minWidth: maxWidth, maxWidth: maxWidth, minHeight: Targets.touch),
          parentUsesSize: true,
        );
        (child.parentData! as _ActionsParentData).offset = Offset(0, y);
        y += child.size.height + DialogActions.stackSpacing;
      }
      size = constraints.constrain(Size(maxWidth, y - DialogActions.stackSpacing));
      return;
    }
    var height = 0.0;
    var width = 0.0;
    for (final child in kids) {
      child.layout(BoxConstraints(maxWidth: maxWidth), parentUsesSize: true);
      height = math.max(height, child.size.height);
      width += child.size.width;
    }
    width += DialogActions.rowSpacing * (kids.length - 1);
    size = constraints.constrain(Size(width, height));
    // End-aligned: the row starts where it leaves the free space before it.
    final rtl = _textDirection == TextDirection.rtl;
    var x = rtl ? size.width : size.width - width;
    for (final child in kids) {
      final dy = (size.height - child.size.height) / 2;
      if (rtl) x -= child.size.width;
      (child.parentData! as _ActionsParentData).offset = Offset(x, dy);
      x += rtl ? -DialogActions.rowSpacing : child.size.width + DialogActions.rowSpacing;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
