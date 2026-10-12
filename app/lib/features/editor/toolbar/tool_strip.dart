import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../editor_tools.dart';
import 'tool_cluster.dart';

/// The active tool's quick controls (colour and width slots, eraser sizes,
/// laser colours…), cross-fading as the tool changes. With [reserve] it
/// keeps that width whatever the tool (start-aligned), so nothing beside
/// it moves. Rebuilds only itself when tools change.
class ToolStrip extends StatelessWidget {
  const ToolStrip({super.key, required this.tools, this.reserve});

  final ToolSettings tools;

  /// The width to take whatever the tool; null: the strip's own width.
  final double? reserve;

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final active = editorTools(tools).firstWhere((d) => d.tool == tools.tool);
        final strip = active.strip;
        final child = strip == null
            ? const SizedBox(key: ValueKey('no-strip'), height: 1)
            : KeyedSubtree(key: ValueKey(active.tool), child: strip(context, active.openOptions));
        final switcher = AnimatedSwitcher(
          duration: reduced ? Duration.zero : Motion.fast,
          layoutBuilder: (current, previous) =>
              Stack(alignment: AlignmentDirectional.centerStart, children: [...previous, ?current]),
          child: child,
        );
        return SizedBox(
          width: reserve,
          height: ToolCluster.height,
          child: Align(alignment: AlignmentDirectional.centerStart, child: switcher),
        );
      },
    );
  }
}
