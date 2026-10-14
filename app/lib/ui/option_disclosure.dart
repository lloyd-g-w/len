import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_theme.dart';
import 'group_header.dart';

/// A collapsible section: its label, an optional [summary] and a chevron,
/// then [child] when open.
class OptionDisclosure extends StatelessWidget {
  const OptionDisclosure({
    super.key,
    required this.label,
    required this.open,
    required this.onToggle,
    required this.child,
    this.summary,
  });

  final String label;

  /// What the section holds, at a glance ("3 colours, 3 sizes").
  final String? summary;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(
          height: Hairline.width,
          thickness: Hairline.width,
          color: theme.colorScheme.outlineVariant,
        ),
        Semantics(
          button: true,
          expanded: open,
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(Radii.sm),
            child: SizedBox(
              height: Targets.menuRow,
              child: Row(
                children: [
                  Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
                  if (summary case final summary?) ...[
                    Text(summary, style: theme.textTheme.bodySmall),
                    const SizedBox(width: Gaps.xs),
                  ],
                  EndChevron(
                    child: AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: Motion.fast,
                      child: Icon(
                        Symbols.expand_more_sharp,
                        size: Glyphs.bar,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: Motion.fast,
          curve: Motion.standard,
          alignment: Alignment.topCenter,
          child: open ? child : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
