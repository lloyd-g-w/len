import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/notebook_style.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/context_menu_keys.dart';
import '../../../ui/roving_focus.dart';

/// The new-notebook sheet's saved notebook styles: one chip each (its
/// cover colour and name; the default says so) that fills in the whole
/// form, then "Save as style…". Tapping the chosen style again, a long
/// press or a right click opens its menu (default, rename, delete).
class StyleRow extends StatelessWidget {
  const StyleRow({
    super.key,
    required this.styles,
    required this.selected,
    required this.onApply,
    required this.onMenu,
    this.onSave,
  });

  final List<NotebookStyle> styles;

  /// The id of the style the form matches, if any.
  final String? selected;
  final ValueChanged<NotebookStyle> onApply;

  /// Opens [NotebookStyle]'s menu at a global position.
  final void Function(NotebookStyle style, Offset at) onMenu;

  /// Saves the form as a style; null hides "Save as style…" (the form
  /// matches a style, or uses one of the user's image templates).
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final save = onSave;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: RovingGroup(
        axis: Axis.horizontal,
        single: true,
        child: Row(
          children: [
            for (final style in styles) ...[
              _StyleChip(
                key: ValueKey('style-${style.id}'),
                style: style,
                selected: style.id == selected,
                onTap: (at) => style.id == selected ? onMenu(style, at) : onApply(style),
                onMenu: (at) => onMenu(style, at),
              ),
              const SizedBox(width: Gaps.sm),
            ],
            if (save != null) _SaveChip(onTap: save),
          ],
        ),
      ),
    );
  }
}

/// The outline and plate of the sheet's chips (as `EvenChoices`): a Rule
/// edge; selected, an Ink plate.
class _ChipFrame extends StatelessWidget {
  const _ChipFrame({
    super.key,
    required this.selected,
    required this.onTap,
    this.onMenu,
    required this.children,
  });

  final bool selected;
  final ValueChanged<Offset> onTap;
  final ValueChanged<Offset>? onMenu;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(Radii.sm);
    final menu = onMenu;
    return RovingItem(
      stop: selected,
      child: ContextMenuKeys(
        onMenu: menu == null ? null : () => menu(_center(context)),
        child: Material(
          color: selected ? Surfaces.pressed(scheme) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: selected ? Colors.transparent : scheme.outlineVariant),
          ),
          child: InkWell(
            onTap: () => onTap(_center(context)),
            onLongPress: menu == null ? null : () => menu(_center(context)),
            onSecondaryTapUp: menu == null ? null : (d) => menu(d.globalPosition),
            borderRadius: radius,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: Targets.of(context, 40)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.xs),
                child: Row(mainAxisSize: MainAxisSize.min, children: children),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Offset _center(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero));
  }
}

class _StyleChip extends StatelessWidget {
  const _StyleChip({
    super.key,
    required this.style,
    required this.selected,
    required this.onTap,
    required this.onMenu,
  });

  final NotebookStyle style;
  final bool selected;
  final ValueChanged<Offset> onTap;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: style.isDefault ? '${style.name}, default style' : '${style.name} style',
      hint: selected ? 'Double tap for options' : null,
      excludeSemantics: true,
      child: _ChipFrame(
        selected: selected,
        onTap: onTap,
        onMenu: onMenu,
        children: [
          // A tiny cover: the colour the notebook gets.
          Container(
            width: 12,
            height: 16,
            decoration: BoxDecoration(
              color: Color(style.choice.coverColor),
              borderRadius: BorderRadius.circular(Radii.xs),
            ),
          ),
          const SizedBox(width: Gaps.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              style.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (style.isDefault) ...[
            const SizedBox(width: Gaps.sm),
            Text('Default', style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// "Save as style…": names what the form shows now.
class _SaveChip extends StatelessWidget {
  const _SaveChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: 'Save as style…',
      excludeSemantics: true,
      child: _ChipFrame(
        key: const ValueKey('save-style'),
        selected: false,
        onTap: (_) => onTap(),
        children: [
          Icon(Symbols.add_sharp, size: Glyphs.menu, color: color),
          const SizedBox(width: Gaps.xs),
          Text('Save as style…', style: theme.textTheme.labelLarge?.copyWith(color: color)),
        ],
      ),
    );
  }
}
