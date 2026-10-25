import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Where the docked main toolbar is, so its sub-bar can hang centred under
/// it: [SubBarAnchor] (around the toolbar in the top bar) reports its rect
/// in the coordinates of this scope's child (the chrome's stack), and
/// [SubBarHanger] (a layer of that stack) centres the sub-bar on it.
///
/// The rect is read once layout is done (after the frame), so it is always
/// the laid-out one; it changes only when the bar's layout does. Until it
/// is known, the sub-bar is centred on the pane.
class SubBarAnchors extends StatefulWidget {
  const SubBarAnchors({super.key, required this.child});

  final Widget child;

  @override
  State<SubBarAnchors> createState() => _SubBarAnchorsState();
}

class _SubBarAnchorsState extends State<SubBarAnchors> {
  final ValueNotifier<Rect?> _rect = ValueNotifier(null);
  final GlobalKey _space = GlobalKey();

  @override
  void dispose() {
    _rect.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AnchorScope(
    rect: _rect,
    space: _space,
    child: KeyedSubtree(key: _space, child: widget.child),
  );
}

class _AnchorScope extends InheritedWidget {
  const _AnchorScope({required this.rect, required this.space, required super.child});

  final ValueNotifier<Rect?> rect;
  final GlobalKey space;

  @override
  bool updateShouldNotify(_AnchorScope old) => old.rect != rect || old.space != space;
}

/// Marks the main toolbar for its sub-bar (see [SubBarAnchors]).
class SubBarAnchor extends SingleChildRenderObjectWidget {
  const SubBarAnchor({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAnchor(context.dependOnInheritedWidgetOfExactType<_AnchorScope>());

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderAnchor).scope = context
          .dependOnInheritedWidgetOfExactType<_AnchorScope>();
}

class _RenderAnchor extends RenderProxyBox {
  _RenderAnchor(this.scope);

  _AnchorScope? scope;
  bool _scheduled = false;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    // Painted whenever it may have moved: report once the frame is done.
    if (_scheduled || scope == null) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final scope = this.scope;
      final space = scope?.space.currentContext?.findRenderObject();
      if (scope == null || !attached || !hasSize || space is! RenderBox || !space.attached) {
        return;
      }
      scope.rect.value = MatrixUtils.transformRect(getTransformTo(space), Offset.zero & size);
    });
  }

  @override
  void detach() {
    // The bar went (the toolbar left the top bar): no anchor to hang from.
    final scope = this.scope;
    if (scope != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        // (Unless the chrome went too, and its notifier with it.)
        if (!attached && scope.space.currentContext != null) scope.rect.value = null;
      });
    }
    super.detach();
  }
}

/// A band of the chrome's stack (full width) holding the sub-bar centred
/// under the main toolbar's [SubBarAnchor], kept [margin] inside the band.
class SubBarHanger extends StatelessWidget {
  const SubBarHanger({super.key, required this.margin, required this.child});

  /// Room the sub-bar keeps from the band's ends (safe areas, the page
  /// sidebar, the edge gap).
  final EdgeInsets margin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_AnchorScope>();
    if (scope == null) return CustomSingleChildLayout(delegate: _Hang(null, margin), child: child);
    return ValueListenableBuilder(
      valueListenable: scope.rect,
      builder: (context, rect, child) =>
          CustomSingleChildLayout(delegate: _Hang(rect?.center.dx, margin), child: child),
      child: child,
    );
  }
}

class _Hang extends SingleChildLayoutDelegate {
  _Hang(this.centre, this.margin);

  /// Where to centre the child across; null: the middle of the room.
  final double? centre;
  final EdgeInsets margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints.loose(
    Size(math.max(0, constraints.maxWidth - margin.horizontal), constraints.maxHeight),
  );

  @override
  Offset getPositionForChild(Size size, Size child) {
    final room = size.width - margin.horizontal;
    final centre = this.centre ?? margin.left + room / 2;
    final x = (centre - child.width / 2)
        .clamp(margin.left, math.max(margin.left, size.width - margin.right - child.width))
        .toDouble();
    return Offset(x, 0);
  }

  @override
  bool shouldRelayout(_Hang old) => old.centre != centre || old.margin != margin;
}
