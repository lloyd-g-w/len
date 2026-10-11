import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'field_border.dart';

/// Component themes shared by the light and dark [AppTheme]s.
extension ThemeComponents on ThemeData {
  ThemeData applyComponentThemes(ColorScheme scheme) {
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control));
    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.control),
      side: BorderSide(color: scheme.outlineVariant),
    );
    final dark = scheme.brightness == Brightness.dark;
    final menuColor = dark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest;
    FilledFieldBorder field(BorderSide side) =>
        FilledFieldBorder(borderSide: side, borderRadius: BorderRadius.circular(Radii.control));
    return copyWith(
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // A tint of the text colour, so fields stand out on any container
        // (dialogs, sheets, cards) in both themes.
        fillColor: scheme.onSurface.withValues(alpha: dark ? 0.08 : 0.055),
        contentPadding: const EdgeInsets.symmetric(horizontal: Gaps.lg, vertical: Gaps.md + 2),
        border: field(BorderSide.none),
        enabledBorder: field(BorderSide.none),
        focusedBorder: field(BorderSide(color: scheme.primary, width: 1.5)),
        errorBorder: field(BorderSide(color: scheme.error)),
        focusedErrorBorder: field(BorderSide(color: scheme.error, width: 1.5)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
        elevation: 2,
        highlightElevation: 4,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: rounded,
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: Gaps.xl - 4),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: rounded,
          minimumSize: const Size(64, 44),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: rounded, minimumSize: const Size(48, 40)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: rounded,
          side: BorderSide(color: scheme.outlineVariant),
          selectedBackgroundColor: scheme.secondaryContainer,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
        side: BorderSide(color: scheme.outlineVariant),
        // Unselected chips are outlined only, so they never read as holes
        // in a lighter dialog or sheet.
        backgroundColor: Colors.transparent,
        selectedColor: scheme.secondaryContainer,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: menuColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sheet)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: menuColor,
        elevation: 6,
        shadowColor: Colors.black38,
        shape: menuShape,
        menuPadding: const EdgeInsets.symmetric(vertical: Gaps.xs + 2),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(menuColor),
          shape: WidgetStatePropertyAll(menuShape),
          elevation: const WidgetStatePropertyAll(6),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: Gaps.xs + 2)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: rounded,
        insetPadding: const EdgeInsets.all(Gaps.lg),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
        height: 68,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      listTileTheme: ListTileThemeData(
        shape: rounded,
        contentPadding: const EdgeInsets.symmetric(horizontal: Gaps.lg),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Icon(Icons.check_rounded, size: 14, color: dark ? null : scheme.primary)
              : null,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          color: dark ? scheme.surfaceContainerHighest : const Color(0xFF2A2A30),
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        textStyle: TextStyle(color: dark ? scheme.onSurface : Colors.white, fontSize: 12),
      ),
      scrollbarTheme: const ScrollbarThemeData(radius: Radius.circular(Radii.pill)),
    );
  }
}
