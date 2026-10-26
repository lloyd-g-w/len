import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../domain/text/text_data.dart';
import '../../../../ui/app_theme.dart';
import '../../../../ui/group_header.dart';
import '../../../../ui/menus.dart';

/// The choices of paragraph spacing, [current] checked (none: mixed).
List<PopupMenuEntry<ParagraphSpacing>> paragraphSpacingItems(ParagraphSpacing? current) => [
  for (final s in ParagraphSpacing.values) MenuRow(value: s, label: s.label, checked: s == current),
];

/// The format bar's paragraph spacing: None / Small / Medium / Large below
/// each paragraph of the box. Its glyph is filled while there is some.
class ParagraphSpacingButton extends StatelessWidget {
  const ParagraphSpacingButton({super.key, required this.spacing, required this.onSelected});

  final ParagraphSpacing spacing;
  final ValueChanged<ParagraphSpacing> onSelected;

  @override
  Widget build(BuildContext context) => MenuIconButton<ParagraphSpacing>(
    key: const ValueKey('paragraph-spacing'),
    tooltip: 'Paragraph spacing',
    onSelected: onSelected,
    items: () => paragraphSpacingItems(spacing),
    icon: Icon(
      Symbols.format_line_spacing_rounded,
      size: Glyphs.bar,
      fill: spacing == ParagraphSpacing.none ? 0 : 1,
    ),
  );
}

/// "Paragraph spacing … None ⌄" as a row of an options popover (as
/// `FontMenuRow`): the whole row opens the choices.
class ParagraphSpacingRow extends StatelessWidget {
  const ParagraphSpacingRow({super.key, required this.spacing, required this.onSelected});

  /// Null: "Mixed" (text boxes spaced differently).
  final ParagraphSpacing? spacing;
  final ValueChanged<ParagraphSpacing> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MenuButton<ParagraphSpacing>(
      key: const ValueKey('paragraph-spacing-row'),
      tooltip: 'Paragraph spacing',
      onSelected: onSelected,
      items: () => paragraphSpacingItems(spacing),
      // (At least a row's height: large text wraps the label.)
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: Targets.menuRowHeight(context)),
        child: Row(
          children: [
            Expanded(child: Text('Paragraph spacing', style: theme.textTheme.labelLarge)),
            Text(spacing?.label ?? 'Mixed', style: theme.textTheme.bodyMedium),
            const SizedBox(width: Gaps.xs),
            EndChevron(
              child: Icon(
                Symbols.expand_more_rounded,
                size: Glyphs.bar,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
