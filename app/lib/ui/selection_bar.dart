import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_theme.dart';
import 'floating_panel.dart';
import 'labelled_action.dart';
import 'menus.dart';

/// A command of a [SelectionBar].
class SelectionCommand {
  const SelectionCommand({
    required this.icon,
    required this.label,
    required this.onPressed,
    String? tooltip,
    this.destructive = false,
    this.filled = false,
    this.overflow,
  }) : tooltip = tooltip ?? label;

  final IconData icon;

  /// The name under the glyph ("Move to folder…").
  final String label;

  /// The tooltip, and the name in the ⋯ menu (default: [label]).
  final String tooltip;
  final VoidCallback onPressed;

  /// Drawn in `error` (Delete, Trash).
  final bool destructive;

  /// The glyph's filled form (a state that is on).
  final bool filled;

  /// Where the bar is short of room, commands with an [overflow] go into
  /// ⋯, the lowest first; null: never.
  final int? overflow;
}

/// The selection bar of the library and the page overview (UX_AUDIT
/// R8-13, R9), one component with one shape everywhere: a floating panel
/// at the bottom (thumb reach) with Done (✕), the count and Select all on
/// top, and the [commands] in a row under them, each a glyph with its name
/// under it, as wide as its name needs and the rest shared. Names
/// keep one size: when they don't fit, commands go into a ⋯ menu in their
/// [SelectionCommand.overflow] order, and if that isn't enough the bar
/// shows glyphs alone, with tooltips.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.title,
    required this.onDone,
    required this.allSelected,
    required this.onSelectAll,
    required this.commands,
    this.enabled = true,
  });

  /// "3 selected", or "Select pages" before anything is.
  final String title;
  final VoidCallback onDone;

  /// Whether everything is selected: the button then selects none.
  final bool allSelected;
  final VoidCallback onSelectAll;
  final List<SelectionCommand> commands;

  /// Whether the commands can run (something is selected).
  final bool enabled;

  /// The widest the bar gets.
  static const double maxWidth = 620;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final head = [
      IconButton(tooltip: 'Done', icon: const Icon(Symbols.close_sharp), onPressed: onDone),
      Expanded(
        child: Text(
          title,
          style: theme.textTheme.labelLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      TextButton(onPressed: onSelectAll, child: Text(allSelected ? 'Select none' : 'Select all')),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.lg),
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxWidth),
            child: FloatingPanel(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(Gaps.xs),
                child: LayoutBuilder(
                  builder: (context, box) => _layout(context, head, box.maxWidth),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, List<Widget> head, double width) {
    final plan = _plan(context, width);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: head),
        Row(
          children: [
            for (final c in plan.shown)
              Expanded(
                flex: _flex(context, c.label),
                child: _action(context, c, labels: plan.labels),
              ),
            if (plan.more.isNotEmpty)
              Expanded(
                flex: _flex(context, _moreLabel),
                child: _more(context, plan.more, labels: plan.labels),
              ),
          ],
        ),
      ],
    );
  }

  /// The commands of the second row, those in ⋯, and whether names show.
  ({List<SelectionCommand> shown, List<SelectionCommand> more, bool labels}) _plan(
    BuildContext context,
    double width,
  ) {
    final shown = [...commands];
    final more = <SelectionCommand>[];
    bool fits() {
      final labels = [for (final c in shown) c.label, if (more.isNotEmpty) _moreLabel];
      final needed = labels.fold(0.0, (sum, l) => sum + _slotWidth(context, l));
      return needed + Gaps.xs * (labels.length - 1) <= width;
    }

    final order = [
      for (final c in commands)
        if (c.overflow != null) c,
    ]..sort((a, b) => a.overflow!.compareTo(b.overflow!));
    for (final c in order) {
      if (fits()) break;
      shown.remove(c);
      more.add(c);
    }
    // The menu lists them in the bar's order.
    more.sort((a, b) => commands.indexOf(a).compareTo(commands.indexOf(b)));
    return (shown: shown, more: more, labels: fits());
  }

  static const _moreLabel = 'More';

  /// A second-row slot's share: what its name needs.
  static int _flex(BuildContext context, String label) => _slotWidth(context, label).round();

  /// What a command with [label] needs: its name and a little room, at
  /// least a touch target.
  static double _slotWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: LabelledAction.labelStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return math.max(LabelledAction.minWidth, width + LabelledAction.labelPadding);
  }

  Widget _action(BuildContext context, SelectionCommand c, {required bool labels}) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: c.tooltip,
      excludeFromSemantics: labels && c.label == c.tooltip,
      child: LabelledAction(
        icon: c.icon,
        label: c.label,
        color: c.destructive ? scheme.error : null,
        filled: c.filled,
        showLabel: labels,
        onPressed: enabled ? c.onPressed : null,
      ),
    );
  }

  Widget _more(BuildContext context, List<SelectionCommand> more, {required bool labels}) {
    return Builder(
      builder: (anchor) => Tooltip(
        message: 'More',
        excludeFromSemantics: labels,
        child: LabelledAction(
          icon: Symbols.more_horiz_sharp,
          label: _moreLabel,
          showLabel: labels,
          onPressed: enabled
              ? () => unawaited(
                  showMenuBelow<SelectionCommand>(
                    anchor,
                    items: [
                      for (final c in more)
                        MenuRow(
                          value: c,
                          icon: c.icon,
                          label: c.tooltip,
                          destructive: c.destructive,
                          filledIcon: c.filled,
                        ),
                    ],
                  ).then((c) => c?.onPressed()),
                )
              : null,
        ),
      ),
    );
  }
}
