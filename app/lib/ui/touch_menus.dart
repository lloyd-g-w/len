import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Makes menu rows 48 dp high on touch devices (REDESIGN §5; 44 with a
/// pointer, from the theme): [Targets.menuRowHeight], by input, not width.
/// Wraps the app (`MaterialApp.builder`).
class TouchMenus extends StatelessWidget {
  const TouchMenus({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Targets.menuRowHeight(context) <= Targets.menuRow) return child;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        menuButtonTheme: MenuButtonThemeData(
          style: theme.menuButtonTheme.style?.copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(0, Targets.touch)),
          ),
        ),
      ),
      child: child,
    );
  }
}
