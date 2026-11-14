import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';

/// The notebook title in the top bar (start-aligned, with an optional
/// quiet subtitle); tap to rename. Where both lines don't fit the bar's
/// height (large text) the subtitle is left out, for screen readers only.
class TitleButton extends StatelessWidget {
  const TitleButton({super.key, required this.title, required this.onRename, this.subtitle});

  final String title;

  /// A quiet second line (e.g. "Page 3 of 12").
  final String? subtitle;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleStyle = theme.textTheme.titleMedium;
    final subtitleStyle = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    // A button to screen readers: the title, then what it does.
    return LayoutBuilder(
      builder: (context, constraints) {
        final subtitle = this.subtitle;
        final both =
            subtitle == null ||
            _height(context, title, titleStyle) +
                    _height(context, subtitle, subtitleStyle) +
                    2 * Gaps.xxs <=
                constraints.maxHeight;
        return _button(
          context,
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
            semanticsLabel: both ? null : '$title, $subtitle',
          ),
          subtitle: both && subtitle != null
              ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: subtitleStyle)
              : null,
        );
      },
    );
  }

  /// The height of one line of [text] in [style] at the context's text size.
  static double _height(BuildContext context, String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  Widget _button(BuildContext context, {required Widget title, Widget? subtitle}) {
    return Semantics(
      button: true,
      child: Tooltip(
        message: 'Rename',
        child: InkWell(
          onTap: onRename,
          borderRadius: BorderRadius.circular(Radii.sm),
          child: ConstrainedBox(
            // 48 dp tall where fingers are the pointer (Android's minimum).
            constraints: BoxConstraints(
              maxWidth: 360,
              minHeight: Targets.touchFirst ? Targets.touch : Targets.bar,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: Gaps.xxs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, ?subtitle],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
