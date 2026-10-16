import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/adaptive_popover.dart';
import '../../../ui/app_theme.dart';
import '../editor_tools.dart';
import 'insert_menu.dart';
import 'tool_cluster.dart';

/// The phone toolbar's tool button `[✎▾]`: the active tool on the neutral
/// plate with a chevron. Tap: the [ToolSwitcherPanel] (every tool and
/// Insert in a 4 × 2 grid); long press: the active tool's options. A
/// [PreviousToolButton] usually sits beside it. While the editor reads
/// ([ToolSettings.reading]) it is the tool alone in a Pencil outline, no
/// tool in hand: a tap writes with it.
class ToolSwitcherButton extends StatelessWidget {
  const ToolSwitcherButton({super.key, required this.tools, this.insert});

  final ToolSettings tools;

  /// Insert ⊕, offered as the grid's last tile.
  final InsertActions? insert;

  /// Width of the button (tool glyph plus chevron).
  static const double width = 52;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final active = editorTools(tools).firstWhere((d) => d.tool == tools.tool);
        final reading = tools.reading;
        void open() => reading ? tools.pick(tools.tool) : _open(context);
        void options() => active.openOptions(context);
        // A 40-dp plate in a 48-dp hit area on touch.
        return Tooltip(
          message: reading
              ? '${active.label}: tap to write'
              : '${active.label}: tap to switch tools',
          child: Semantics(
            button: true,
            label: reading
                ? 'Reading. Write with the ${active.label.toLowerCase()}'
                : 'Tool: ${active.label}. Switch tools',
            excludeSemantics: true,
            onTap: open,
            onLongPress: options,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: open,
              onLongPress: options,
              child: SizedBox(
                width: width,
                height: Targets.barHit(context),
                child: Center(
                  child: Material(
                    key: const ValueKey('tool-switcher'),
                    color: reading ? Colors.transparent : Surfaces.pressed(scheme),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.xs),
                      side: reading
                          ? BorderSide(color: scheme.outline, width: Hairline.width)
                          : BorderSide.none,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.xs),
                      onTap: open,
                      onLongPress: options,
                      child: SizedBox(
                        width: width,
                        height: Targets.bar,
                        child: IconTheme.merge(
                          data: IconThemeData(color: scheme.onSurface),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ToolGlyph(descriptor: active, filled: !reading),
                              if (!reading) ...[
                                const SizedBox(width: Gaps.xxs),
                                Icon(
                                  Symbols.expand_more_sharp,
                                  size: Glyphs.badge,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _open(BuildContext anchor) => showAdaptivePopover<void>(
    context: anchor,
    width: ToolSwitcherPanel.width,
    sheetOnPhones: false,
    builder: (popover) => ToolSwitcherPanel(tools: tools, insert: insert, anchor: anchor),
  );
}

/// The phone toolbar's previous tool, next to the [ToolSwitcherButton]:
/// one tap swaps it with the active tool (pen ↔ eraser, pen ↔
/// highlighter), as GoodNotes' and Notewise's phone bars switch tools.
class PreviousToolButton extends StatelessWidget {
  const PreviousToolButton({super.key, required this.tools});

  final ToolSettings tools;

  /// The button's width: a full touch target.
  static double get width => Targets.touchFirst ? Targets.touch : Targets.bar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final previous = editorTools(tools).firstWhere((d) => d.tool == tools.previousTool);
        return Tooltip(
          message: 'Switch to ${previous.label.toLowerCase()}',
          child: Semantics(
            button: true,
            label: 'Switch to ${previous.label.toLowerCase()}',
            excludeSemantics: true,
            onTap: tools.togglePrevious,
            child: InkWell(
              key: const ValueKey('previous-tool'),
              borderRadius: BorderRadius.circular(Radii.xs),
              onTap: tools.togglePrevious,
              child: SizedBox(
                width: width,
                height: width,
                child: Center(
                  child: IconTheme.merge(
                    data: IconThemeData(color: scheme.onSurfaceVariant),
                    child: ToolGlyph(descriptor: previous),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Every tool and Insert ⊕ as labelled tiles, 4 × 2. Tapping a tool
/// switches to it and closes; tapping the active tool opens its options
/// (as in the full toolbar); Insert opens its menu.
class ToolSwitcherPanel extends StatelessWidget {
  const ToolSwitcherPanel({super.key, required this.tools, required this.anchor, this.insert});

  final ToolSettings tools;
  final InsertActions? insert;

  /// Where popovers and menus opened from here are anchored (the button).
  final BuildContext anchor;

  static const double _tile = 68;

  /// The popover's width: four tiles, their gaps and its padding.
  static const double width = 4 * _tile + 3 * Gaps.xs + 2 * Gaps.lg;

  @override
  Widget build(BuildContext context) {
    final descriptors = editorTools(tools);
    final insert = this.insert;
    return Wrap(
      spacing: Gaps.xs,
      runSpacing: Gaps.xs,
      children: [
        for (final d in descriptors)
          _Tile(
            key: ValueKey('switch-${d.tool.name}'),
            label: d.shortLabel,
            selected: d.tool == tools.tool,
            glyph: ToolGlyph(descriptor: d, filled: d.tool == tools.tool),
            onTap: () {
              final reopen = d.tool == tools.tool && !tools.reading;
              tools.pick(d.tool);
              Navigator.of(context).pop();
              if (reopen && anchor.mounted) d.openOptions(anchor);
            },
          ),
        if (insert != null)
          _Tile(
            key: const ValueKey('switch-insert'),
            label: 'Insert',
            selected: false,
            // In a tool glyph's 26-dp box, icon on top, so its label lines
            // up with the tools'.
            glyph: const SizedBox.square(
              dimension: 26,
              child: Align(
                alignment: Alignment.topCenter,
                child: Icon(Symbols.add_circle_sharp, size: Glyphs.bar),
              ),
            ),
            onTap: () {
              Navigator.of(context).pop();
              if (anchor.mounted) insert.showAt(anchor);
            },
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.label,
    required this.selected,
    required this.glyph,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Widget glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? Surfaces.pressed(scheme) : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.xs),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.xs),
          onTap: onTap,
          child: SizedBox(
            width: ToolSwitcherPanel._tile,
            height: 64,
            child: IconTheme.merge(
              data: IconThemeData(color: fg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  glyph,
                  const SizedBox(height: Gaps.xs),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
