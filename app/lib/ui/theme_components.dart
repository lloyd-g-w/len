import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_theme.dart';
import 'field_border.dart';

/// Component themes shared by the light and dark [AppTheme]s: radii from
/// [Radii], surfaces from [Surfaces], no Material elevation (menus excepted,
/// see [menuElevation]), and a calm `onSurface` overlay instead of ripples.
extension ThemeComponents on ThemeData {
  /// Menus are the one place Flutter offers no `BoxShadow` hook, so they
  /// keep a Material elevation, softened to match [Shadows.high].
  static const double menuElevation = 8;

  ThemeData applyComponentThemes(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    final control = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm));
    final overlay = Surfaces.overlay(scheme.brightness);
    final menuShape = Surfaces.shape(scheme, Radii.md);
    final shadow = Colors.black.withValues(alpha: dark ? 0.5 : 0.16);
    final calm = calmOverlay(scheme);
    final scrim = Surfaces.scrim(scheme.brightness);
    FilledFieldBorder field(BorderSide side) =>
        FilledFieldBorder(borderSide: side, borderRadius: BorderRadius.circular(Radii.sm));
    return copyWith(
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // A tint of the text colour, so fields stand out on any container
        // (dialogs, sheets, cards) in both themes.
        fillColor: scheme.onSurface.withValues(alpha: dark ? 0.08 : 0.055),
        contentPadding: const EdgeInsets.symmetric(horizontal: Gaps.md + 2, vertical: Gaps.md),
        border: field(BorderSide.none),
        enabledBorder: field(BorderSide.none),
        focusedBorder: field(BorderSide(color: scheme.primary, width: 1.5)),
        errorBorder: field(BorderSide(color: scheme.error)),
        focusedErrorBorder: field(BorderSide(color: scheme.error, width: 1.5)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        // The primary button's colours (dark mode lifts the accent).
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        splashColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: control,
          minimumSize: const Size(64, 40),
          padding: const EdgeInsets.symmetric(horizontal: Gaps.lg + 2),
          elevation: 0,
          // Disabled: no accent, but its label still reads (Material's 38 %
          // was grey on grey on dark dialogs).
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: scheme.onSurfaceVariant,
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: control,
          minimumSize: const Size(64, 40),
          side: BorderSide(color: scheme.outlineVariant),
          splashFactory: NoSplash.splashFactory,
        ).copyWith(overlayColor: calm),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: control,
          minimumSize: const Size(48, 40),
          splashFactory: NoSplash.splashFactory,
        ).copyWith(overlayColor: calm),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: control,
          iconSize: Glyphs.bar,
          splashFactory: NoSplash.splashFactory,
        ).copyWith(overlayColor: calm),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: control,
          side: BorderSide(color: scheme.outlineVariant),
          // A firmer plate than a pressed row's, so the choice reads at a
          // glance in both themes.
          selectedBackgroundColor: scheme.onSurface.withValues(
            alpha: scheme.brightness == Brightness.dark ? 0.2 : 0.12,
          ),
          selectedForegroundColor: scheme.onSurface,
          foregroundColor: scheme.onSurfaceVariant,
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          splashFactory: NoSplash.splashFactory,
        ).copyWith(overlayColor: calm),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xs)),
        side: BorderSide(color: scheme.outlineVariant),
        // Unselected chips are outlined only, so they never read as holes
        // in a lighter dialog or sheet.
        backgroundColor: Colors.transparent,
        selectedColor: Surfaces.pressed(scheme),
        elevation: 0,
        pressElevation: 0,
        iconTheme: const IconThemeData(size: Glyphs.menu),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: overlay,
        modalBackgroundColor: overlay,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        modalBarrierColor: scrim,
        dragHandleColor: scheme.outline.withValues(alpha: 0.5),
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: overlay,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        barrierColor: scrim,
        shape: Surfaces.shape(scheme, Radii.lg),
        titleTextStyle: textTheme.titleMedium,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        insetPadding: const EdgeInsets.all(Gaps.xl),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: overlay,
        surfaceTintColor: Colors.transparent,
        elevation: menuElevation,
        shadowColor: shadow,
        shape: menuShape,
        menuPadding: const EdgeInsets.symmetric(vertical: Gaps.xs + 2),
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      ),
      menuTheme: MenuThemeData(
        // A rounded chevron, not Material's filled triangle.
        submenuIcon: const WidgetStatePropertyAll(
          Icon(Symbols.chevron_right_rounded, size: Glyphs.menu),
        ),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(overlay),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(shadow),
          shape: WidgetStatePropertyAll(menuShape),
          elevation: const WidgetStatePropertyAll(menuElevation),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: Gaps.xs + 2)),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: MenuItemButton.styleFrom(
          minimumSize: const Size(0, Targets.menuRow),
          padding: const EdgeInsets.symmetric(horizontal: Gaps.md + 2),
          iconSize: Glyphs.menu,
          iconColor: scheme.onSurfaceVariant,
          textStyle: textTheme.labelLarge,
          splashFactory: NoSplash.splashFactory,
        ).copyWith(overlayColor: calm),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        backgroundColor: dark ? scheme.surfaceContainerHighest : const Color(0xFF2A2A30),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: dark ? scheme.onSurface : Colors.white,
        ),
        actionTextColor: dark ? scheme.primary : const Color(0xFFB4C3FF),
        insetPadding: const EdgeInsets.all(Gaps.lg),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Surfaces.chrome(scheme),
        indicatorColor: Surfaces.pressed(scheme),
        surfaceTintColor: Colors.transparent,
        height: 64,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Surfaces.chrome(scheme),
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: Surfaces.chrome(scheme),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrimColor: scrim,
      ),
      listTileTheme: ListTileThemeData(
        shape: control,
        contentPadding: const EdgeInsets.symmetric(horizontal: Gaps.lg),
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: textTheme.bodyMedium,
        subtitleTextStyle: textTheme.bodySmall,
        selectedColor: scheme.onSurface,
        selectedTileColor: Surfaces.pressed(scheme),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Icon(Symbols.check_rounded, size: 14, color: dark ? null : scheme.primary)
              : null,
        ),
      ),
      sliderTheme: SliderThemeData(overlayColor: Surfaces.pressed(scheme)),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          color: dark ? scheme.surfaceContainerHighest : const Color(0xFF2A2A30),
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: dark ? scheme.onSurface : Colors.white),
      ),
      scrollbarTheme: const ScrollbarThemeData(radius: Radius.circular(Radii.pill)),
      // A track that shows on dark dialogs too (the secondary container
      // nearly matches them).
      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearTrackColor: scheme.onSurface.withValues(alpha: 0.12),
      ),
      // Flutter's own back, close and drawer buttons use Symbols too.
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const Icon(Symbols.arrow_back_rounded),
        closeButtonIconBuilder: (_) => const Icon(Symbols.close_rounded),
        drawerButtonIconBuilder: (_) => const Icon(Symbols.menu_rounded),
        endDrawerButtonIconBuilder: (_) => const Icon(Symbols.menu_rounded),
      ),
    );
  }

  /// The press, hover and focus overlay of quiet controls: `onSurface` at
  /// 8 % / 12 % (dark) when pressed or focused, half that on hover. Use it
  /// as `overlayColor` in a custom `ButtonStyle`.
  static WidgetStateProperty<Color?> calmOverlay(ColorScheme scheme) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed) || states.contains(WidgetState.focused)) {
          return Surfaces.pressed(scheme);
        }
        if (states.contains(WidgetState.hovered)) return Surfaces.hovered(scheme);
        return null;
      });
}
