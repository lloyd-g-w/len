import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A command of a selection bar on touch: its glyph with its name under
/// it (a tooltip needs a long press there, so a bare glyph is a guess).
/// Wrap it in `Expanded` to share a bar's width with its neighbours.
class LabelledAction extends StatelessWidget {
  const LabelledAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.filled = false,
  });

  final IconData icon;
  final String label;

  /// Null disables it.
  final VoidCallback? onPressed;

  /// The glyph's and label's colour (destructive commands: `error`).
  final Color? color;

  /// The glyph's filled form (a state that is on).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: color ?? Theme.of(context).colorScheme.onSurface,
        minimumSize: const Size(56, 56),
        // Five share a phone's width: the label needs the room.
        padding: const EdgeInsets.symmetric(horizontal: Gaps.xxs),
      ),
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: Glyphs.bar, fill: filled ? 1 : 0),
          const SizedBox(height: Gaps.xxs),
          // One line always: a tight bar (five on a phone, large text)
          // scales the name down rather than cutting it.
          FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, softWrap: false)),
        ],
      ),
    );
  }
}
