import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import '../../ui/dialog_or_sheet.dart';
import '../../ui/section_label.dart';
import '../../ui/sheet_parts.dart';
import 'keyboard_shortcuts.dart';

/// Shows every keyboard shortcut, grouped.
Future<void> showKeyboardShortcuts(BuildContext context) => showDialogOrSheet<void>(
  context: context,
  maxWidth: 560,
  maxHeight: 720,
  sheetHeightFactor: 0.85,
  builder: (context, wide) => _ShortcutsSheet(wide: wide),
);

class _ShortcutsSheet extends StatelessWidget {
  const _ShortcutsSheet({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(Gaps.xl, wide ? Gaps.lg : 0, Gaps.xl, Gaps.sm),
          child: SheetHeader(
            title: 'Keyboard shortcuts',
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, Gaps.xl),
            children: [
              for (final group in shortcutGroups) ...[
                Padding(
                  padding: const EdgeInsets.only(top: Gaps.xl, bottom: Gaps.xs),
                  child: SectionLabel(group.title),
                ),
                // A ruled table: a hairline between lines.
                for (final (i, item) in group.items.indexed) ...[
                  if (i > 0)
                    Divider(
                      height: Hairline.width,
                      thickness: Hairline.width,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gaps.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(item.label, style: theme.textTheme.bodyMedium)),
                        const SizedBox(width: Gaps.md),
                        Flexible(
                          child: Text(
                            shownKeys(item),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFeatures: AppTheme.tabularFigures,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
