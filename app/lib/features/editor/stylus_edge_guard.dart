import 'package:flutter/widgets.dart';

import '../../platform/stylus_edges.dart';
import 'split/split_view.dart';

/// Holds [StylusEdges] while the editor around [child] shows: its route is
/// the current one (no dialog or screen over it) and its split-view pane
/// isn't parked. Then a stylus at the screen's edge writes instead of
/// going Back (Android gesture navigation; fingers still go Back).
class StylusEdgeGuard extends StatefulWidget {
  /// Guards the edges while [child] shows, through [edges] (the app's by
  /// default).
  const StylusEdgeGuard({super.key, required this.child, this.edges});

  /// The editor.
  final Widget child;

  /// Overrides the app's [stylusEdges] (tests).
  final StylusEdges? edges;

  @override
  State<StylusEdgeGuard> createState() => _StylusEdgeGuardState();
}

class _StylusEdgeGuardState extends State<StylusEdgeGuard> {
  StylusEdges? _held;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(StylusEdgeGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.edges != widget.edges) _update();
  }

  @override
  void dispose() {
    _set(null);
    super.dispose();
  }

  void _update() {
    final shows = (ModalRoute.isCurrentOf(context) ?? true) && !SplitView.parkedOf(context);
    _set(shows ? widget.edges ?? stylusEdges : null);
  }

  void _set(StylusEdges? edges) {
    if (identical(edges, _held)) return;
    _held?.release();
    _held = edges?..hold();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
