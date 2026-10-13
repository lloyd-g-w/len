import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'app_theme.dart';

/// Lays out same-size items (swatches, icon tiles) in even rows that
/// fill the width: as many columns as fit, preferring a count that
/// divides the items into full rows (14 colours → two rows of 7, never
/// 4 + 4 + 4 + 2), with the leftover space spread between the columns.
/// Supports intrinsic sizing, so it works inside dialogs.
class EvenGrid extends MultiChildRenderObjectWidget {
  const EvenGrid({
    super.key,
    required this.itemExtent,
    double? minItemExtent,
    required super.children,
    this.minSpacing = Gaps.xs,
    this.runSpacing = Gaps.sm,
    this.maxSpacing = Gaps.lg,
    this.touchTargets = false,
  }) : minItemExtent = minItemExtent ?? itemExtent;

  /// Width (and height) of every child.
  final double itemExtent;

  /// Items may shrink to this to make rows even (e.g. 7 + 7 rather than
  /// 6 + 6 + 2 on a phone).
  final double minItemExtent;

  final double minSpacing, runSpacing, maxSpacing;

  /// On phones, cells grow to [Targets.touch] and need no spacing of their
  /// own: children that centre a smaller visual in their cell (and take taps
  /// across all of it) get full-size touch targets.
  final bool touchTargets;

  @override
  RenderEvenGrid createRenderObject(BuildContext context) => RenderEvenGrid(_spec(context));

  @override
  void updateRenderObject(BuildContext context, RenderEvenGrid renderObject) =>
      renderObject.spec = _spec(context);

  EvenGridSpec _spec(BuildContext context) {
    final grow = touchTargets && Targets.of(context, minItemExtent) > minItemExtent;
    return EvenGridSpec(
      itemExtent: grow ? math.max(itemExtent, Targets.touch) : itemExtent,
      minItemExtent: grow ? Targets.touch : minItemExtent,
      minSpacing: grow ? 0 : minSpacing,
      runSpacing: grow ? 0 : runSpacing,
      maxSpacing: maxSpacing,
    );
  }
}

/// The geometry of an [EvenGrid] and how it resolves for a width.
@immutable
class EvenGridSpec {
  const EvenGridSpec({
    required this.itemExtent,
    required this.minItemExtent,
    required this.minSpacing,
    required this.runSpacing,
    required this.maxSpacing,
  });

  final double itemExtent, minItemExtent, minSpacing, runSpacing, maxSpacing;

  /// Columns, item extent and column spacing for [count] items in [width].
  ({int columns, double extent, double spacing}) resolve(int count, double width) {
    if (count == 0) return (columns: 1, extent: itemExtent, spacing: 0);
    final fit = math.max(1, ((width + minSpacing) / (itemExtent + minSpacing)).floor());
    var columns = _columnsFor(count, fit);
    var extent = itemExtent;
    if (count % columns != 0) {
      // The next even split, if the items may shrink enough for it.
      for (var c = columns + 1; c <= count; c++) {
        if (count % c != 0) continue;
        final shrunk = (width - (c - 1) * minSpacing) / c;
        if (shrunk >= minItemExtent) {
          columns = c;
          extent = math.min(itemExtent, shrunk);
        }
        break;
      }
    }
    final spacing = columns < 2
        ? 0.0
        : ((width - columns * extent) / (columns - 1)).clamp(minSpacing, maxSpacing);
    return (columns: columns, extent: extent, spacing: spacing);
  }

  /// The largest divisor of [count] that keeps rows at least half as wide
  /// as they could be (10 colours where 9 fit: 5 + 5, not 9 + 1), else
  /// [fit].
  static int _columnsFor(int count, int fit) {
    if (count <= fit) return count;
    for (var c = fit; c * 2 >= fit && c > 1; c--) {
      if (count % c == 0) return c;
    }
    return fit;
  }

  Size sizeFor(int count, double width) {
    final r = resolve(count, width);
    final rows = (count / r.columns).ceil();
    final w = r.columns * r.extent + (r.columns - 1) * r.spacing;
    return Size(w, rows * r.extent + math.max(0, rows - 1) * runSpacing);
  }

  @override
  bool operator ==(Object other) =>
      other is EvenGridSpec &&
      other.itemExtent == itemExtent &&
      other.minItemExtent == minItemExtent &&
      other.minSpacing == minSpacing &&
      other.runSpacing == runSpacing &&
      other.maxSpacing == maxSpacing;

  @override
  int get hashCode => Object.hash(itemExtent, minItemExtent, minSpacing, runSpacing, maxSpacing);
}

class _EvenGridParentData extends ContainerBoxParentData<RenderBox> {}

/// Render object of [EvenGrid].
class RenderEvenGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _EvenGridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _EvenGridParentData> {
  RenderEvenGrid(this._spec);

  EvenGridSpec _spec;
  EvenGridSpec get spec => _spec;
  set spec(EvenGridSpec value) {
    if (value == _spec) return;
    _spec = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _EvenGridParentData) child.parentData = _EvenGridParentData();
  }

  @override
  double computeMinIntrinsicWidth(double height) => spec.itemExtent;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      childCount * spec.itemExtent + math.max(0, childCount - 1) * spec.minSpacing;

  @override
  double computeMinIntrinsicHeight(double width) => _heightFor(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _heightFor(width);

  double _heightFor(double width) => spec
      .sizeFor(childCount, width.isFinite ? width : computeMaxIntrinsicWidth(double.infinity))
      .height;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(spec.sizeFor(childCount, _width(constraints)));

  double _width(BoxConstraints constraints) => constraints.hasBoundedWidth
      ? constraints.maxWidth
      : computeMaxIntrinsicWidth(double.infinity);

  @override
  void performLayout() {
    final width = _width(constraints);
    final r = spec.resolve(childCount, width);
    final itemConstraints = BoxConstraints.tight(Size.square(r.extent));
    var i = 0;
    var child = firstChild;
    while (child != null) {
      child.layout(itemConstraints);
      final row = i ~/ r.columns, column = i % r.columns;
      (child.parentData! as _EvenGridParentData).offset = Offset(
        column * (r.extent + r.spacing),
        row * (r.extent + spec.runSpacing),
      );
      child = childAfter(child);
      i++;
    }
    size = constraints.constrain(spec.sizeFor(childCount, width));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}
