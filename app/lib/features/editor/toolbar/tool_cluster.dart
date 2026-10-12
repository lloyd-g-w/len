import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../editor_tools.dart';
import 'insert_menu.dart';
import 'toolbar_metrics.dart';

/// The tools in their fixed order, then Insert ⊕. One neutral `xs` plate
/// sits behind the active tool and slides to the next one ([Motion.fast];
/// it jumps with reduced motion). Rebuilds only itself when tools change.
class ToolCluster extends StatelessWidget {
  const ToolCluster({super.key, required this.tools, this.insert});

  final ToolSettings tools;

  /// Insert ⊕ after the tools; null leaves it out.
  final InsertActions? insert;

  /// Height of the cluster: the tool cells' hit size.
  static double get height => Targets.touchFirst ? Targets.touch : Targets.bar;

  /// Width of the cluster, with or without Insert ⊕, [compact] or not.
  static double widthFor({required bool insert, bool compact = false}) =>
      (EditorTool.values.length + (insert ? 1 : 0)) * ToolbarMetrics.toolCell(compact: compact);

  @override
  Widget build(BuildContext context) {
    final compact = ToolbarDensity.compactOf(context);
    final cell = ToolbarMetrics.toolCell(compact: compact);
    final height = ToolCluster.height;
    final reduced = Motion.reduced(context);
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final descriptors = editorTools(tools);
        final index = descriptors.indexWhere((d) => d.tool == tools.tool);
        return SizedBox(
          width: widthFor(insert: insert != null, compact: compact),
          height: height,
          child: Stack(
            children: [
              if (index >= 0)
                AnimatedPositioned(
                  key: const ValueKey('tool-plate'),
                  duration: reduced ? Duration.zero : Motion.fast,
                  curve: Motion.standard,
                  left: index * cell + (cell - Targets.bar) / 2,
                  top: (height - Targets.bar) / 2,
                  width: Targets.bar,
                  height: Targets.bar,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Surfaces.pressed(scheme),
                      borderRadius: BorderRadius.circular(Radii.xs),
                    ),
                  ),
                ),
              Row(
                children: [
                  for (final d in descriptors)
                    SizedBox(
                      width: cell,
                      height: height,
                      child: Center(
                        child: ToolButton(
                          descriptor: d,
                          selected: d.tool == tools.tool,
                          onSelect: () => tools.tool = d.tool,
                        ),
                      ),
                    ),
                  if (insert case final insert?) InsertButton(actions: insert, size: cell),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A tool toggle (40 × 40, no background of its own: the cluster's plate
/// marks the active tool). Inking tools show their colour as a small bar
/// under the glyph. Tapping the active tool, long-pressing or
/// right-clicking any tool opens its options.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.descriptor,
    required this.selected,
    required this.onSelect,
  });

  final ToolDescriptor descriptor;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    void openOptions() {
      if (!selected) onSelect();
      descriptor.openOptions(context);
    }

    return GestureDetector(
      onLongPress: openOptions,
      onSecondaryTap: openOptions,
      child: IconButton(
        tooltip: descriptor.tooltip,
        isSelected: selected,
        constraints: const BoxConstraints.tightFor(width: Targets.bar, height: Targets.bar),
        padding: EdgeInsets.zero,
        onPressed: selected ? openOptions : onSelect,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xs)),
        ),
        icon: ToolGlyph(descriptor: descriptor, filled: selected),
      ),
    );
  }
}

/// A tool's icon with its ink colour as a small bar underneath.
class ToolGlyph extends StatelessWidget {
  const ToolGlyph({super.key, required this.descriptor, this.filled = false});

  final ToolDescriptor descriptor;

  /// Fills symbol glyphs (the active tool).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = descriptor.inkColor?.call();
    // Dark inks on dark chrome (and white on light) get a firmer edge.
    final nearSurface =
        color != null &&
        (Color(color).computeLuminance() - scheme.surface.computeLuminance()).abs() < 0.1;
    return SizedBox.square(
      dimension: 26,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          IconTheme.merge(
            data: IconThemeData(size: Glyphs.bar, fill: filled ? 1 : 0),
            child: descriptor.icon,
          ),
          if (color != null)
            Positioned(
              bottom: 0,
              child: Container(
                width: 14,
                height: 3,
                decoration: BoxDecoration(
                  color: Color(color),
                  borderRadius: BorderRadius.circular(1.5),
                  border: Border.all(
                    color: nearSurface
                        ? scheme.onSurfaceVariant
                        : scheme.outline.withValues(alpha: 0.6),
                    width: nearSurface ? 1 : 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A 1-px divider between toolbar clusters (they sit 12 apart).
class ToolbarDivider extends StatelessWidget {
  const ToolbarDivider({super.key, this.height = 24});

  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: height,
    margin: const EdgeInsets.symmetric(horizontal: (ToolbarMetrics.divider - 1) / 2),
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}
