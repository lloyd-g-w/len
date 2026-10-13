import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/theme_components.dart';

/// Whether the chrome under it recedes: the other pane of a split view is
/// in use (`SplitController.isDimmed`). [Receding] reads it.
class RecedeScope extends InheritedWidget {
  const RecedeScope({super.key, required this.dimmed, required super.child});

  final bool dimmed;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RecedeScope>()?.dimmed ?? false;

  @override
  bool updateShouldNotify(RecedeScope old) => old.dimmed != dimmed;
}

/// What sits on a bar or palette (icons, text, the tools), receding while
/// its [RecedeScope] is dimmed ([Motion.fast]): chrome colours (the
/// scheme's foreground roles, glyphs and text) fade toward the bar's
/// surface, to [opacity] of their strength. Ink stays true: colour swatches
/// and a tool's colour underline are content, drawn in their own colours.
/// The bars' surfaces stay as they are: a whole bar at partial opacity
/// reads as grey over a light page in dark mode.
class Receding extends StatelessWidget {
  const Receding({super.key, required this.child});

  final Widget child;

  /// How strong chrome colours stay while receded.
  static const double opacity = 0.6;

  static final Expando<ThemeData> _receded = Expando();
  static final Expando<bool> _isReceded = Expando();

  /// [theme] with its foreground colours faded toward its surface, [t] of
  /// the way (0: as it is, 1: to [opacity]). A receded theme stays as it
  /// is, so nested [Receding]s fade once.
  static ThemeData recede(ThemeData theme, [double t = 1]) {
    if (t <= 0 || (_isReceded[theme] ?? false)) return theme;
    if (t < 1) return _recede(theme, t);
    return _receded[theme] ??= _recede(theme, 1);
  }

  static ThemeData _recede(ThemeData theme, double t) {
    final s = theme.colorScheme;
    final strength = 1 - t * (1 - opacity);
    Color fade(Color c) => Color.lerp(s.surface, c, strength)!;
    final scheme = s.copyWith(
      primary: fade(s.primary),
      onSurface: fade(s.onSurface),
      onSurfaceVariant: fade(s.onSurfaceVariant),
      outline: fade(s.outline),
      outlineVariant: fade(s.outlineVariant),
    );
    TextStyle? text(TextStyle? t) => t?.copyWith(color: t.color == null ? null : fade(t.color!));
    final tt = theme.textTheme;
    final receded = theme
        .copyWith(
          colorScheme: scheme,
          iconTheme: theme.iconTheme.copyWith(color: fade(theme.iconTheme.color ?? s.onSurface)),
          textTheme: TextTheme(
            displayLarge: text(tt.displayLarge),
            displayMedium: text(tt.displayMedium),
            displaySmall: text(tt.displaySmall),
            headlineLarge: text(tt.headlineLarge),
            headlineMedium: text(tt.headlineMedium),
            headlineSmall: text(tt.headlineSmall),
            titleLarge: text(tt.titleLarge),
            titleMedium: text(tt.titleMedium),
            titleSmall: text(tt.titleSmall),
            bodyLarge: text(tt.bodyLarge),
            bodyMedium: text(tt.bodyMedium),
            bodySmall: text(tt.bodySmall),
            labelLarge: text(tt.labelLarge),
            labelMedium: text(tt.labelMedium),
            labelSmall: text(tt.labelSmall),
          ),
        )
        .applyComponentThemes(scheme);
    _isReceded[receded] = true;
    return receded;
  }

  @override
  Widget build(BuildContext context) {
    // The theme as given (not localized: popovers opened from here lerp
    // between their themes, whose text styles must stay alike).
    final localized = Theme.of(context);
    final theme = context.findAncestorWidgetOfExactType<Theme>()?.data ?? localized;
    // Rebuilt per frame rather than an AnimatedTheme's lerp, which mixes
    // localized and given text styles.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: RecedeScope.of(context) ? 1 : 0),
      duration: Motion.fast,
      curve: Motion.standard,
      child: child,
      builder: (context, t, child) {
        final data = recede(theme, t);
        return Theme(
          data: data,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: data.textTheme.bodyMedium?.color),
            child: child!,
          ),
        );
      },
    );
  }
}
