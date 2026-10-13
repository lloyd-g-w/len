import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_theme.dart';
import 'field_border.dart';
import 'group_header.dart';
import 'theme_controls.dart';

/// Component themes shared by the light and dark [AppTheme]s (DESIGN §6):
/// radii from [Radii], surfaces from [Surfaces], hairlines instead of
/// fills, no Material elevation (menus excepted, see [menuElevation]), Ink
/// primary buttons, and a calm ink overlay instead of ripples. Selection
/// controls are in `theme_controls.dart`.
extension ThemeComponents on ThemeData {
  /// Menus are the one place Flutter offers no `BoxShadow` hook, so they
  /// keep a Material elevation, softened to match [Shadows.high].
  static const double menuElevation = 6;

  ThemeData applyComponentThemes(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    final control = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm));
    final overlay = Surfaces.overlay(scheme.brightness);
    final menuShape = Surfaces.shape(scheme, Radii.md);
    final shadow = Colors.black.withValues(alpha: dark ? 0.6 : 0.22);
    final calm = calmOverlay(scheme);
    final scrim = Surfaces.scrim(scheme.brightness);
    final hairline = BorderSide(color: scheme.outlineVariant, width: Hairline.width);
    RuledFieldBorder field(BorderSide side) =>
        RuledFieldBorder(borderSide: side, borderRadius: const Radius.circular(Radii.xs));
    return copyWith(
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          side: hairline,
        ),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // A tint of the ink, so fields read on any surface in both themes.
        fillColor: scheme.onSurface.withValues(alpha: dark ? 0.06 : 0.04),
        hoverColor: scheme.onSurface.withValues(alpha: dark ? 0.04 : 0.02),
        contentPadding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.md),
        // The rule a field is written on: Graphite, so it reads as a line
        // (and a field's edge) at a glance.
        border: field(BorderSide(color: scheme.onSurfaceVariant)),
        enabledBorder: field(BorderSide(color: scheme.onSurfaceVariant)),
        focusedBorder: field(BorderSide(color: scheme.primary, width: Hairline.rule)),
        disabledBorder: field(BorderSide(color: scheme.outlineVariant)),
        errorBorder: field(BorderSide(color: scheme.error)),
        focusedErrorBorder: field(BorderSide(color: scheme.error, width: Hairline.rule)),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        // An Ink square: the primary button's colours.
        backgroundColor: scheme.onSurface,
        foregroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        splashColor: Colors.transparent,
        hoverColor: scheme.surface.withValues(alpha: 0.12),
        focusColor: scheme.surface.withValues(alpha: 0.16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? scheme.outlineVariant : scheme.onSurface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? scheme.onSurfaceVariant : scheme.surface,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? scheme.onSurfaceVariant : scheme.surface,
          ),
          overlayColor: _inverseOverlay(scheme),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          shape: WidgetStatePropertyAll(control),
          minimumSize: const WidgetStatePropertyAll(Size(64, 40)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Gaps.lg + 2)),
          elevation: const WidgetStatePropertyAll(0),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: control,
          minimumSize: const Size(64, 40),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: Gaps.lg + 2),
          splashFactory: NoSplash.splashFactory,
        ).copyWith(overlayColor: calm),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: control,
          minimumSize: const Size(48, 40),
          foregroundColor: scheme.onSurface,
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: Gaps.md),
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
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: overlay,
        modalBackgroundColor: overlay,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        modalBarrierColor: scrim,
        dragHandleColor: scheme.outline,
        dragHandleSize: const Size(32, 3),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
          side: Surfaces.border(scheme) ?? BorderSide.none,
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
        menuPadding: const EdgeInsets.symmetric(vertical: Gaps.xs),
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      ),
      menuTheme: MenuThemeData(
        // A sharp chevron, not Material's filled triangle, its tip on the
        // row's end edge.
        submenuIcon: const WidgetStatePropertyAll(MenuChevron()),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(overlay),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(shadow),
          shape: WidgetStatePropertyAll(menuShape),
          elevation: const WidgetStatePropertyAll(menuElevation),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: Gaps.xs)),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: MenuItemButton.styleFrom(
          minimumSize: const Size(0, Targets.menuRow),
          padding: const EdgeInsets.symmetric(horizontal: Gaps.md),
          iconSize: Glyphs.menu,
          iconColor: scheme.onSurfaceVariant,
          foregroundColor: scheme.onSurface,
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(),
          splashFactory: NoSplash.splashFactory,
        ).copyWith(overlayColor: calm),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        // In dark mode the slab is light, like the paper it often floats
        // over: a Pencil edge keeps it apart.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: scheme.brightness == Brightness.dark
              ? BorderSide(color: scheme.outline)
              : BorderSide.none,
        ),
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        closeIconColor: scheme.onInverseSurface,
        insetPadding: const EdgeInsets.all(Gaps.lg),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Surfaces.chrome(scheme),
        indicatorColor: Surfaces.pressed(scheme),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
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
        centerTitle: false,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: Surfaces.chrome(scheme),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrimColor: scrim,
        // Square, with a hairline edge: a sheet slid over the desk.
        shape: Border(right: hairline),
        endShape: Border(left: hairline),
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
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: Hairline.width,
      ),
      tabBarTheme: TabBarThemeData(
        // The current tab carries the margin rule.
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: scheme.primary, width: Hairline.rule),
        ),
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: textTheme.labelLarge,
        dividerColor: scheme.outlineVariant,
        dividerHeight: Hairline.width,
        overlayColor: calm,
        splashFactory: NoSplash.splashFactory,
      ),
      // Flutter's own back, close and drawer buttons use Symbols too.
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const Icon(Symbols.arrow_back_sharp),
        closeButtonIconBuilder: (_) => const Icon(Symbols.close_sharp),
        drawerButtonIconBuilder: (_) => const Icon(Symbols.menu_sharp),
        endDrawerButtonIconBuilder: (_) => const Icon(Symbols.menu_sharp),
      ),
    ).applyControlThemes(scheme);
  }

  /// The press, hover and focus overlay of quiet controls: ink at 8 % /
  /// 12 % (dark) when pressed or focused, half that on hover. Use it as
  /// `overlayColor` in a custom `ButtonStyle`.
  static WidgetStateProperty<Color?> calmOverlay(ColorScheme scheme) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed) || states.contains(WidgetState.focused)) {
          return Surfaces.pressed(scheme);
        }
        if (states.contains(WidgetState.hovered)) return Surfaces.hovered(scheme);
        return null;
      });

  /// An Ink-filled icon button, the one primary control of a strip (the
  /// audio player's play button): `IconButton.filled(style: inkIconButton(scheme))`.
  static ButtonStyle inkIconButton(ColorScheme scheme) => IconButton.styleFrom(
    backgroundColor: scheme.onSurface,
    foregroundColor: scheme.surface,
    disabledBackgroundColor: scheme.outlineVariant,
    disabledForegroundColor: scheme.onSurfaceVariant,
  ).copyWith(overlayColor: _inverseOverlay(scheme));

  /// The overlay of Ink-filled controls: the Board colour over the ink.
  static WidgetStateProperty<Color?> _inverseOverlay(ColorScheme scheme) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed) || states.contains(WidgetState.focused)) {
          return scheme.surface.withValues(alpha: 0.20);
        }
        if (states.contains(WidgetState.hovered)) return scheme.surface.withValues(alpha: 0.12);
        return null;
      });
}
