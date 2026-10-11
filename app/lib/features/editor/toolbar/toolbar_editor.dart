import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../editor_tools.dart';
import '../pen/slot_button.dart';
import '../toolbar_buttons.dart';
import 'favourite_pens.dart';
import 'toolbar_config.dart';

/// The toolbar in edit mode ("⋯" → Customise toolbar…): every tool as a
/// tile — tap to show or hide it, hold and drag to reorder — then the
/// favourite pens (× removes one, + pins the pen in use), Reset and Done.
/// Changes apply (and persist) at once through [onChanged].
class ToolbarEditor extends StatelessWidget {
  const ToolbarEditor({
    super.key,
    required this.tools,
    required this.config,
    required this.onChanged,
    required this.onDone,
  });

  final ToolSettings tools;
  final ToolbarConfig config;
  final ValueChanged<ToolbarConfig> onChanged;
  final VoidCallback onDone;

  static const double _tileWidth = 64;
  static const double _height = 64;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Hidden tools are listed too (dimmed), in their place.
    final ordered = ToolbarConfig(order: config.order).arrange(editorTools(tools), (d) => d.tool);
    final shown = [for (final d in ordered) d.tool];
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) => FloatingPanel(
        padding: const EdgeInsets.fromLTRB(Gaps.sm, Gaps.xs, Gaps.sm, Gaps.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: Gaps.xs, top: Gaps.xxs),
              child: Text(
                'Tap a tool to show or hide it · hold and drag to reorder',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final room = constraints.maxWidth;
                final tools = ordered.length * _tileWidth;
                final favourites = _favouritesWidth;
                // One row when everything fits; otherwise (phones) the
                // tools get their own row, favourites and actions below.
                if (tools + favourites + _actionsWidth <= room) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: _height,
                        width: tools,
                        child: _list(context, ordered, shown),
                      ),
                      const ToolbarDivider(),
                      _favourites(context),
                      ..._actions(),
                    ],
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: _height,
                      width: math.min(tools, room),
                      child: _list(context, ordered, shown),
                    ),
                    SizedBox(
                      width: math.min(room, math.max(tools, favourites + _actionsWidth)),
                      child: Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: _favourites(context),
                            ),
                          ),
                          ..._actions(),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Room for the divider, Reset and Done.
  static const double _actionsWidth = 13 + 72 + 4 + 80;

  /// The favourites with their label and "add" button.
  double get _favouritesWidth => 84 + config.favourites.length * _favouriteWidth + SlotButton.size;

  /// A favourite with room for its remove badge.
  static const double _favouriteWidth = 46;

  List<Widget> _actions() => [
    const ToolbarDivider(),
    if (!config.isDefault)
      TextButton(onPressed: () => onChanged(const ToolbarConfig()), child: const Text('Reset')),
    const SizedBox(width: Gaps.xs),
    FilledButton.tonal(onPressed: onDone, child: const Text('Done')),
  ];

  Widget _list(BuildContext context, List<ToolDescriptor> ordered, List<EditorTool> shown) {
    return ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      buildDefaultDragHandles: false,
      itemCount: ordered.length,
      onReorderItem: (from, to) => onChanged(config.reorder(shown, from, to)),
      itemBuilder: (context, i) {
        final d = ordered[i];
        return ReorderableDelayedDragStartListener(
          key: ValueKey('edit-${d.tool.name}'),
          index: i,
          child: _ToolTile(
            descriptor: d,
            hidden: config.hidden.contains(d.tool),
            onToggle: () => onChanged(config.toggle(d.tool)),
            onMove: (delta) {
              final to = i + delta;
              if (to < 0 || to >= ordered.length) return;
              onChanged(config.reorder(shown, i, to));
            },
            width: _tileWidth,
          ),
        );
      },
    );
  }

  Widget _favourites(BuildContext context) {
    final current = FavouritePen.current(tools);
    final canAdd =
        current != null &&
        !config.favourites.contains(current) &&
        config.favourites.length < ToolbarConfig.maxFavourites;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gaps.xs),
          child: Text(
            'Favourites',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        for (final (i, pen) in config.favourites.indexed)
          SizedBox(
            width: _favouriteWidth,
            height: SlotButton.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                FavouriteGlyph(pen: pen),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Tooltip(
                    message: 'Remove favourite: ${describeFavourite(pen)}',
                    child: InkResponse(
                      key: ValueKey('remove-favourite-$i'),
                      radius: 12,
                      onTap: () => onChanged(config.removeFavourite(i)),
                      child: CircleAvatar(
                        radius: 7,
                        backgroundColor: scheme.inverseSurface,
                        child: Icon(Icons.close_rounded, size: 12, color: scheme.onInverseSurface),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        SizedBox.square(
          dimension: SlotButton.size,
          child: IconButton(
            key: const ValueKey('add-favourite'),
            tooltip: canAdd
                ? 'Add the pen in use to favourites'
                : current == null
                ? 'Pick a pen or highlighter to add it to favourites'
                : 'Already a favourite',
            padding: EdgeInsets.zero,
            onPressed: canAdd ? () => onChanged(config.addFavourite(current)) : null,
            icon: const Icon(Icons.star_border_rounded, size: 20),
          ),
        ),
      ],
    );
  }
}

/// A tool in edit mode: tap toggles it, dimmed with a crossed eye when
/// hidden. Screen readers get "Move left / right" actions.
class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.descriptor,
    required this.hidden,
    required this.onToggle,
    required this.onMove,
    required this.width,
  });

  final ToolDescriptor descriptor;
  final bool hidden;
  final VoidCallback onToggle;
  final ValueChanged<int> onMove;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = scheme.onSurfaceVariant;
    return Semantics(
      label: '${descriptor.label}, ${hidden ? 'hidden' : 'shown'}',
      hint: 'Tap to ${hidden ? 'show' : 'hide'}',
      customSemanticsActions: {
        CustomSemanticsAction(label: 'Move left'): () => onMove(-1),
        CustomSemanticsAction(label: 'Move right'): () => onMove(1),
      },
      child: Tooltip(
        message: hidden ? 'Show ${descriptor.label}' : 'Hide ${descriptor.label}',
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.control),
          onTap: onToggle,
          child: SizedBox(
            width: width,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedOpacity(
                  opacity: hidden ? 0.38 : 1,
                  duration: Motion.fast,
                  child: IconTheme.merge(
                    data: IconThemeData(color: fg),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ToolGlyph(descriptor: descriptor),
                        const SizedBox(height: Gaps.xxs),
                        Text(
                          descriptor.shortLabel,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: theme.textTheme.labelSmall?.copyWith(color: fg),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 6,
                  child: Icon(
                    hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    size: 14,
                    color: hidden ? scheme.onSurfaceVariant : scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
