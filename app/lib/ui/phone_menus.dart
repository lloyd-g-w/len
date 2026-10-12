import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Makes menu rows 48 dp high on phones (REDESIGN §5; 44 elsewhere, from
/// the theme). Wraps the app (`MaterialApp.builder`).
class PhoneMenus extends StatelessWidget {
  const PhoneMenus({super.key, required this.child});

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
