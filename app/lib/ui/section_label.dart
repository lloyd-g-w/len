import 'package:flutter/material.dart';

/// The heading of a group of items (library "Folders", template
/// categories, sidebar sections): sentence case, quiet, semibold.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  /// The style, for headings that need to lay out their own text.
  static TextStyle? style(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: style(context), maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}
