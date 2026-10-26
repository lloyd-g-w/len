import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../../../ui/roving_focus.dart';
import '../../../ui/scroll_fade.dart';
import '../chrome/receding.dart';
import '../editor_tools.dart';
import 'tool_cluster.dart';
import 'toolbar_metrics.dart';

/// Builds the toolbar's sub-bar facing the main bar in the direction
/// `towards` ([ToolSubBar.towards]).
typedef SubBarBuilder = Widget Function(Offset towards);

/// The active tool's quick controls in a pill of their own, attached to
/// the main bar as its child (as Notewise's pen bar hangs under its
/// toolbar): the tool's strip (widths and colours, eraser sizes and
/// mode…), a hairline, then [SubBarOptionsButton] for the tool's options.
///
/// It fades in sliding a little away from the main bar ([towards] points
/// at it; fades only with reduced motion), cross-fades its controls as the
/// tool changes, and is gone for a tool with no quick controls (lasso,
/// text). It runs along the [ToolbarAxis] and scrolls, its ends fading,
/// where it has less room than it needs. Rebuilds only itself when tools
/// change.
class ToolSubBar extends StatelessWidget {
  const ToolSubBar({super.key, required this.tools, this.towards = const Offset(0, -1)});

  final ToolSettings tools;

  /// The direction of the main bar from the sub-bar (up when it hangs
  /// under the bar).
  final Offset towards;

  @override
  Widget build(BuildContext context) {
    final slide = Motion.reduced(context) ? 0.0 : Motion.chromeSlide;
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final active = editorTools(tools).firstWhere((d) => d.tool == tools.tool);
        return AnimatedSwitcher(
          duration: Motion.medium,
          switchInCurve: Motion.standard,
          switchOutCurve: Motion.exit,
          layoutBuilder: (current, previous) =>
              Stack(alignment: Alignment.center, children: [...previous, ?current]),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, child) => Transform.translate(
                offset: towards * slide * (1 - animation.value),
                child: child,
              ),
              child: child,
            ),
          ),
          child: active.strip == null
              ? const SizedBox.shrink(key: ValueKey('no-sub-bar'))
              // One pill for every tool: only its controls cross-fade.
              : _Pill(key: const ValueKey('tool-sub-bar'), descriptor: active),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.descriptor});

  final ToolDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final axis = ToolbarAxis.of(context);
    final horizontal = axis == Axis.horizontal;
    const across = ToolbarMetrics.subBarPadding, along = ToolbarMetrics.subBarEnd;
    return FloatingPanel(
      radius: Radii.pill,
      padding: horizontal
          ? const EdgeInsets.symmetric(horizontal: along, vertical: across)
          : const EdgeInsets.symmetric(horizontal: across, vertical: along),
      child: Receding(
        child: ScrollFade(
          axis: axis,
          child: AnimatedSize(
            duration: Motion.moving(context, Motion.fast),
            curve: Motion.standard,
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: Motion.fast,
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.center, children: [...previous, ?current]),
              child: RovingGroup(
                key: ValueKey(descriptor.tool),
                axis: axis,
                child: SubBarControls(descriptor: descriptor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A sub-bar's controls: the tool's quick controls, then (for a tool with
/// options) a hairline and its options button.
class SubBarControls extends StatelessWidget {
  const SubBarControls({super.key, required this.descriptor});

  final ToolDescriptor descriptor;

  @override
  Widget build(BuildContext context) => Flex(
    direction: ToolbarAxis.of(context),
    mainAxisSize: MainAxisSize.min,
    children: [
      ?descriptor.strip?.call(context),
      if (descriptor.options != null) ...[
        const ToolbarDivider(),
        SubBarOptionsButton(descriptor: descriptor),
      ],
    ],
  );
}

/// The sub-bar's last control (⚙ sliders): opens the tool's options, the
/// same popover as tapping the selected tool, anchored here.
class SubBarOptionsButton extends StatelessWidget {
  const SubBarOptionsButton({super.key, required this.descriptor});

  final ToolDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final cell = ToolbarMetrics.slotOf(context);
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      key: const ValueKey('tool-options'),
      tooltip: '${descriptor.label} options',
      constraints: BoxConstraints.tightFor(width: cell, height: cell),
      padding: EdgeInsets.zero,
      onPressed: () => descriptor.openOptions(context),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: scheme.onSurfaceVariant,
        // Round, to sit in the pill's rounded end.
        shape: const CircleBorder(),
      ),
      icon: const Icon(Symbols.tune_rounded, size: Glyphs.bar),
    );
  }
}
