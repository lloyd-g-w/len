import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';

/// Roving focus (the WAI-ARIA toolbar / radio group pattern): the arrow keys
/// move between the controls inside, in the order they are shown, Home and
/// End to the first and the last, and Tab leaves the group rather than
/// visiting every control.
///
/// Where Tab stops:
/// * [single] groups (segmented controls, swatch grids) are one Tab stop:
///   the control with focus, else the chosen one (a [RovingItem] with
///   `stop`, or [selected]), else the first.
/// * Otherwise (the toolbar, made of several groups of choices) Tab stops
///   at each [RovingItem] whose `stop` is set and at every control outside
///   one.
///
/// At either end the arrows stay put, so they never leak to what is behind
/// the group (in the editor, they turn pages).
class RovingGroup extends StatefulWidget {
  const RovingGroup({
    super.key,
    required this.axis,
    this.single = false,
    this.selected,
    required this.child,
  });

  /// A grid, one Tab stop: ← → step along the reading order, ↑ ↓ to the
  /// nearest control in the row above or below.
  const RovingGroup.grid({super.key, this.selected, required this.child})
    : axis = null,
      single = true;

  /// The direction the controls run in: ← → for a row, ↑ ↓ for a column;
  /// null for a grid ([RovingGroup.grid]).
  final Axis? axis;

  /// Whether the whole group is a single Tab stop.
  final bool single;

  /// In a [single] group without a [RovingItem] stop, the index of the
  /// chosen control (in the order shown) where Tab enters.
  final int? selected;

  final Widget child;

  @override
  State<RovingGroup> createState() => _RovingGroupState();
}

class _RovingGroupState extends State<RovingGroup> {
  late final _policy = _RovingPolicy(this);

  /// The group's own node (its descendants are the controls).
  final FocusNode _group = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
    debugLabel: 'RovingGroup',
  );

  @override
  void dispose() {
    _group.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = widget.child;
    if (widget.single) child = FocusTraversalGroup(policy: _policy, child: child);
    return _Scope(
      group: this,
      child: Focus(focusNode: _group, onKeyEvent: _onKey, child: child),
    );
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final controls = this.controls();
    final focused = FocusManager.instance.primaryFocus;
    final at = controls.indexWhere(
      (n) => n == focused || (focused?.ancestors.contains(n) ?? false),
    );
    if (at < 0) return KeyEventResult.ignored;
    final next = switch (event.logicalKey) {
      LogicalKeyboardKey.home => 0,
      LogicalKeyboardKey.end => controls.length - 1,
      final key => _step(key, controls, at),
    };
    if (next == null) return KeyEventResult.ignored;
    if (next != at && next >= 0 && next < controls.length) {
      final node = controls[next]..requestFocus();
      final context = node.context;
      if (context != null && context.mounted) {
        Scrollable.ensureVisible(context, duration: Motion.moving(context, Motion.fast));
      }
    }
    return KeyEventResult.handled;
  }

  /// Where an arrow [key] goes from `controls[at]`: an index (out of range
  /// at the ends), or null when the key is not an arrow of this group.
  int? _step(LogicalKeyboardKey key, List<FocusNode> controls, int at) {
    final horizontal = key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight;
    final vertical = key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown;
    final back = key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp;
    return switch (widget.axis) {
      Axis.horizontal when horizontal => at + (back ? -1 : 1),
      Axis.vertical when vertical => at + (back ? -1 : 1),
      null when horizontal => at + (back ? -1 : 1),
      null when vertical => _rowStep(controls, at, up: back),
      _ => null,
    };
  }

  /// In a grid, the control in the row above (or below) nearest to
  /// `controls[at]`'s column, or -1 when there is no such row.
  static int _rowStep(List<FocusNode> controls, int at, {required bool up}) {
    final from = controls[at].rect;
    var best = -1;
    var bestDy = double.infinity;
    var bestDx = double.infinity;
    for (final (i, node) in controls.indexed) {
      final r = node.rect;
      final dy = up ? from.center.dy - r.center.dy : r.center.dy - from.center.dy;
      if (dy < from.height / 2) continue;
      final dx = (r.center.dx - from.center.dx).abs();
      // The nearest row first, then the nearest column in it.
      if (dy < bestDy - 1 || (dy <= bestDy + 1 && dx < bestDx)) {
        (best, bestDy, bestDx) = (i, dy, dx);
      }
    }
    return best;
  }

  /// The focusable controls in the group, in the order shown.
  List<FocusNode> controls() {
    final candidates = {
      for (final node in _group.descendants)
        if (node.canRequestFocus && node is! FocusScopeNode && _shown(node)) node,
    };
    // Not a node inside another control (e.g. a button's inner node).
    bool nested(FocusNode node) {
      for (final a in node.ancestors) {
        if (a == _group) return false;
        if (candidates.contains(a)) return true;
      }
      return false;
    }

    return [
      for (final node in candidates)
        if (!nested(node)) node,
    ]..sort(_order);
  }

  /// Along the axis; a grid in reading order (rows, then columns).
  int _order(FocusNode a, FocusNode b) {
    final (ra, rb) = (a.rect, b.rect);
    return switch (widget.axis) {
      Axis.horizontal => ra.center.dx.compareTo(rb.center.dx),
      Axis.vertical => ra.center.dy.compareTo(rb.center.dy),
      null =>
        (ra.center.dy - rb.center.dy).abs() < ra.height / 2
            ? ra.center.dx.compareTo(rb.center.dx)
            : ra.center.dy.compareTo(rb.center.dy),
    };
  }

  /// Where Tab enters a [RovingGroup.single] group, among its traversal
  /// [members].
  FocusNode? entry(List<FocusNode> members) {
    final controls = this.controls().where(members.contains).toList();
    if (controls.isEmpty) return null;
    for (final node in controls) {
      if (node.ancestors.any((a) => a is _StopNode && a.stop && a.group == _group)) return node;
    }
    final selected = widget.selected;
    if (selected != null && selected >= 0 && selected < controls.length) {
      return controls[selected];
    }
    return controls.first;
  }

  static bool _shown(FocusNode node) {
    final box = node.context?.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize;
  }
}

/// Keeps one member of a [RovingGroup.single] group in the Tab order: the
/// focused one while focus is inside, else its entry.
class _RovingPolicy extends ReadingOrderTraversalPolicy {
  _RovingPolicy(this.group);

  final _RovingGroupState group;

  @override
  Iterable<FocusNode> sortDescendants(Iterable<FocusNode> descendants, FocusNode currentNode) {
    final members = descendants.toList();
    for (final m in members) {
      if (m == currentNode || currentNode.ancestors.contains(m)) return [m];
    }
    if (!group.mounted) return super.sortDescendants(descendants, currentNode);
    final entry = group.entry(members);
    return entry == null ? super.sortDescendants(descendants, currentNode) : [entry];
  }
}

class _Scope extends InheritedWidget {
  const _Scope({required this.group, required super.child});

  final _RovingGroupState group;

  @override
  bool updateShouldNotify(_Scope old) => old.group != group;
}

/// One choice in a [RovingGroup]: the arrows reach it either way. Tab
/// enters a [RovingGroup.single] group at the [stop]; in a toolbar it
/// reaches the controls in [child] only when it is a [stop] (the chosen
/// tool, the selected slot). Outside a group it changes nothing.
class RovingItem extends StatefulWidget {
  const RovingItem({super.key, required this.stop, required this.child});

  final bool stop;
  final Widget child;

  @override
  State<RovingItem> createState() => _RovingItemState();
}

class _RovingItemState extends State<RovingItem> {
  // (Always this node, so a choice that becomes the stop keeps its focus.)
  final _node = _StopNode();

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final group = context.dependOnInheritedWidgetOfExactType<_Scope>()?.group;
    _node
      ..stop = widget.stop
      ..group = group?._group;
    return Focus(
      focusNode: _node,
      canRequestFocus: false,
      skipTraversal: true,
      descendantsAreTraversable: widget.stop || group == null || group.widget.single,
      child: widget.child,
    );
  }
}

/// A [RovingItem]'s node: says whether its controls are its group's stop.
class _StopNode extends FocusNode {
  _StopNode() : super(canRequestFocus: false, skipTraversal: true, debugLabel: 'RovingItem');

  bool stop = false;

  /// The node of the [RovingGroup] it belongs to.
  FocusNode? group;
}

/// A [SegmentedButton] as one Tab stop at its chosen segment, the arrows
/// moving between segments ([RovingGroup]).
class RovingSegments extends StatelessWidget {
  const RovingSegments(this.button, {super.key});

  final SegmentedButton<Object?> button;

  @override
  Widget build(BuildContext context) {
    final segments = button.segments;
    final chosen = segments.indexWhere((s) => button.selected.contains(s.value));
    return RovingGroup(
      axis: button.direction,
      single: true,
      // Among the segments that can take focus.
      selected: chosen < 0 ? null : segments.take(chosen).where((s) => s.enabled).length,
      child: button,
    );
  }
}
