import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../ui/app_theme.dart';
import 'notebook_card.dart';

/// The "New…" tile that starts the library grid (GoodNotes style): a
/// quiet, cover-sized plate with a "+", and the label where a notebook's
/// title goes. Sized by the grid like a [NotebookCard].
class NewNotebookTile extends StatefulWidget {
  const NewNotebookTile({super.key, required this.onPressed});

  /// Opens the create flow.
  final VoidCallback onPressed;

  @override
  State<NewNotebookTile> createState() => _NewNotebookTileState();
}

class _NewNotebookTileState extends State<NewNotebookTile> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lifted = _hovered || _focused;
    final radius = BorderRadius.circular(Radii.sm);
    return Semantics(
      button: true,
      label: 'New notebook',
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: Motion.medium,
              curve: Motion.standard,
              decoration: BoxDecoration(
                color: lifted ? scheme.surfaceContainerHigh : scheme.surfaceContainer,
                borderRadius: radius,
                // No outlines in light mode (REDESIGN §1.1). In dark mode a
                // firmer edge than a cover's: the tile is a button, and its
                // face is close to the background.
                border: theme.brightness == Brightness.dark
                    ? Border.all(color: scheme.outline)
                    : null,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: radius,
                  onTap: widget.onPressed,
                  onHover: (h) => setState(() => _hovered = h),
                  onFocusChange: (f) => setState(() => _focused = f),
                  child: Center(
                    child: AnimatedScale(
                      scale: lifted ? 1.1 : 1,
                      duration: Motion.fast,
                      child: Icon(Symbols.add_sharp, size: Glyphs.empty, color: scheme.primary),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The card's caption area (NotebookCard.captionHeight), so the
          // tile's cover matches the covers next to it.
          SizedBox(
            height: NotebookCard.captionHeight(MediaQuery.textScalerOf(context)),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onPressed,
              child: Padding(
                padding: const EdgeInsets.only(left: Gaps.xxs, top: Gaps.sm),
                child: Text('New notebook', style: theme.textTheme.labelLarge, maxLines: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
