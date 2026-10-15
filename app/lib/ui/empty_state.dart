import 'package:flutter/material.dart';

import 'app_theme.dart';

/// An empty view's layout (the library's sections, a folder, a search, the
/// overview's Bookmarked): [art], a title, one line and, under them, what
/// to do next ([action]), a little above the middle. Windows shorter than
/// [artFrom] leave the picture out, so the action shows without scrolling.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.art,
    required this.title,
    required this.message,
    this.action,
  });

  final Widget art;
  final String title;
  final String message;

  /// The next step, if there is one (buttons, laid out by the caller).
  final Widget? action;

  /// Windows shorter than this leave the picture out.
  static const double artFrom = 520;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final short = MediaQuery.sizeOf(context).height < artFrom;
    // A little above the middle, where the eye expects it (a header
    // already sits above it).
    return Align(
      alignment: short ? Alignment.center : const Alignment(0, -0.2),
      child: Padding(
        padding: EdgeInsets.all(short ? Gaps.lg : Gaps.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Motion.slow,
            curve: Motion.standard,
            // A fade only: nothing slides in on its own (DESIGN §5).
            builder: (context, t, child) => Opacity(opacity: t, child: child),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!short) ...[art, const SizedBox(height: Gaps.xl)],
                Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: Gaps.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (action case final action?) ...[const SizedBox(height: Gaps.xl), action],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An empty view's glyph, bare (no disc; DESIGN §6 dialog glyphs).
class EmptyGlyph extends StatelessWidget {
  const EmptyGlyph(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: Glyphs.empty, color: Theme.of(context).colorScheme.onSurfaceVariant);
}
