import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A command of a selection bar on touch: its glyph with its name under
/// it (a tooltip needs a long press there, so a bare glyph is a guess).
/// Wrap it in `Expanded` to share a bar's width with its neighbours.
/// Without [showLabel] it is the glyph alone (the bar gives it a tooltip):
/// a bar whose names don't all fit drops them all rather than shrinking
/// some (UX_AUDIT R8-13).
class LabelledAction extends StatelessWidget {
  const LabelledAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.filled = false,
    this.showLabel = true,
  });

  final IconData icon;
  final String label;

  /// Null disables it.
  final VoidCallback? onPressed;

  /// The glyph's and label's colour (destructive commands: `error`).
  final Color? color;

  /// The glyph's filled form (a state that is on).
  final bool filled;

  /// Whether the name shows under the glyph.
  final bool showLabel;

  /// The narrowest a command gets (a touch target).
  static const double minWidth = Targets.touch;

  /// The room a name takes beside its own width.
  static const double labelPadding = Gaps.xxs * 2;

  /// The style names are set in (the bar measures them with it).
  static TextStyle? labelStyle(BuildContext context) => Theme.of(context).textTheme.labelLarge;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: color ?? Theme.of(context).colorScheme.onSurface,
        minimumSize: const Size(minWidth, 56),
        padding: const EdgeInsets.symmetric(horizontal: labelPadding / 2),
        textStyle: labelStyle(context),
      ),
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: Glyphs.bar, fill: filled ? 1 : 0),
          if (showLabel) ...[
            const SizedBox(height: Gaps.xxs),
            // The bar has made room for it; the ellipsis is only a guard.
            Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}
