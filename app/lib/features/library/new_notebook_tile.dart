import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';

/// The "New…" tile that starts the library grid (GoodNotes style): an
/// outlined, cover-sized card with a "+", and the label where a notebook's
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
    final radius = BorderRadius.circular(Radii.cover);
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
              transform: Matrix4.translationValues(0, lifted ? -4 : 0, 0),
              decoration: BoxDecoration(
                color: lifted ? scheme.surfaceContainer : scheme.surfaceContainerLow,
                borderRadius: radius,
                border: Border.all(
                  color: lifted ? scheme.primary : scheme.outlineVariant,
                  width: lifted ? 1.6 : 1,
                ),
                boxShadow: lifted ? Shadows.low(theme.brightness) : null,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: radius,
                  onTap: widget.onPressed,
                  onHover: (h) => setState(() => _hovered = h),
                  onFocusChange: (f) => setState(() => _focused = f),
                  child: Center(
                    child: Container(
                      width: Gaps.xxxl,
                      height: Gaps.xxxl,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.add_rounded, size: 28, color: scheme.onPrimaryContainer),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Gaps.sm + 2),
          // Lines up with the titles of the notebook cards next to it.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: Padding(
              padding: const EdgeInsets.only(left: Gaps.xxs),
              child: Text(
                'New…',
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
