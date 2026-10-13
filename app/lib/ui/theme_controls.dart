import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'slider_shapes.dart';
import 'theme_components.dart';

/// Themes of the selection and feedback controls (DESIGN §6): segmented
/// controls, chips, switches, sliders, checkboxes, radios, progress,
/// tooltips and scrollbars. Flat, hairline-edged, the accent only where a
/// state is on.
extension ThemeControls on ThemeData {
  ThemeData applyControlThemes(ColorScheme scheme) {
    final calm = ThemeComponents.calmOverlay(scheme);
    final control = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm));
    final off = scheme.brightness == Brightness.dark
        ? scheme.surfaceContainerHighest
        : scheme.outlineVariant;
    bool on(Set<WidgetState> s) => s.contains(WidgetState.selected);
    bool disabled(Set<WidgetState> s) => s.contains(WidgetState.disabled);
    return copyWith(
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(control),
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => on(s) ? Surfaces.selected(scheme) : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => disabled(s)
                ? scheme.onSurface.withValues(alpha: 0.38)
                : on(s)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (s) => on(s) ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
          textStyle: WidgetStateProperty.resolveWith(
            (s) => textTheme.labelLarge?.copyWith(
              fontWeight: on(s) ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          overlayColor: calm,
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xs)),
        side: WidgetStateBorderSide.resolveWith(
          (s) => BorderSide(color: on(s) ? scheme.onSurface : scheme.outline),
        ),
        // Unselected chips are outlined only, so they never read as holes
        // in a lighter dialog or sheet.
        backgroundColor: Colors.transparent,
        selectedColor: Surfaces.selected(scheme),
        checkmarkColor: scheme.onSurface,
        labelStyle: textTheme.labelLarge,
        elevation: 0,
        pressElevation: 0,
        iconTheme: const IconThemeData(size: Glyphs.menu),
      ),
      switchTheme: SwitchThemeData(
        // A flat track and a constant-size thumb without a glyph: off is a
        // Rule track with a Graphite thumb, on is ruling blue with a Sheet
        // thumb.
        thumbIcon: const WidgetStatePropertyAll(Icon(null)),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => disabled(s)
              ? scheme.onSurface.withValues(alpha: 0.3)
              : on(s)
              ? Surfaces.raised(scheme.brightness)
              : scheme.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => disabled(s)
              ? scheme.onSurface.withValues(alpha: 0.08)
              : on(s)
              ? scheme.primary
              : off,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackOutlineWidth: const WidgetStatePropertyAll(0),
        overlayColor: calm,
        splashRadius: 18,
      ),
      sliderTheme: SliderThemeData(
        // A ruled track and an ink tick for a thumb, like a ruler's mark.
        trackHeight: Hairline.rule,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: off,
        disabledActiveTrackColor: scheme.onSurface.withValues(alpha: 0.3),
        disabledInactiveTrackColor: scheme.onSurface.withValues(alpha: 0.1),
        thumbColor: scheme.onSurface,
        disabledThumbColor: scheme.onSurface.withValues(alpha: 0.38),
        overlappingShapeStrokeColor: Surfaces.raised(scheme.brightness),
        thumbShape: const RuleThumbShape(),
        overlayShape: const QuietSliderOverlay(),
        overlayColor: Colors.transparent,
        trackShape: const RectangularSliderTrackShape(),
        tickMarkShape: SliderTickMarkShape.noTickMark,
        valueIndicatorColor: scheme.inverseSurface,
        valueIndicatorTextStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
          fontFeatures: AppTheme.tabularFigures,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xs)),
        side: WidgetStateBorderSide.resolveWith(
          (s) => on(s) ? BorderSide.none : BorderSide(color: scheme.outline, width: 1.5),
        ),
        fillColor: WidgetStateProperty.resolveWith(
          (s) => on(s) ? scheme.primary : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        overlayColor: calm,
        splashRadius: 18,
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => on(s) ? scheme.primary : scheme.outline),
        overlayColor: calm,
        splashRadius: 18,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        // A track that shows on dark dialogs too.
        linearTrackColor: off,
        circularTrackColor: Colors.transparent,
        linearMinHeight: Hairline.rule,
        borderRadius: BorderRadius.zero,
        strokeWidth: Hairline.rule,
        strokeCap: StrokeCap.butt,
        stopIndicatorColor: Colors.transparent,
        trackGap: 0,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 600),
        padding: const EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: Gaps.xs),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(4),
        radius: const Radius.circular(Radii.xs),
        crossAxisMargin: 2,
        thumbColor: WidgetStatePropertyAll(scheme.onSurfaceVariant.withValues(alpha: 0.48)),
      ),
    );
  }
}
