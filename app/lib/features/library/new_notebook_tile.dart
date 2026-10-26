import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../ui/app_theme.dart';
import 'notebook_card.dart';

/// The "New…" tile that starts the library grid (GoodNotes style): a
/// cover-sized outline with a "+", and the label where a notebook's title
/// goes. Sized by the grid like a [NotebookCard].
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
              duration: Motion.fast,
              // A secondary button the size of a cover (DESIGN §6): a
              // Pencil edge, no plate, an Ink "+"; hover is the ink overlay.
              decoration: BoxDecoration(
                color: lifted ? Surfaces.hovered(scheme) : Colors.transparent,
                borderRadius: radius,
                border: Border.all(color: scheme.outline),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: radius,
                  onTap: widget.onPressed,
                  onHover: (h) => setState(() => _hovered = h),
                  onFocusChange: (f) => setState(() => _focused = f),
                  child: Center(
                    child: Icon(Symbols.add_rounded, size: Glyphs.empty, color: scheme.onSurface),
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
