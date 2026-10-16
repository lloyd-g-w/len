import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/context_menu_keys.dart';
import 'sidebar_metrics.dart';

/// The page sidebar's last tile: adds a page at the end; held down (or
/// right-clicked), with a template. A Pencil-edged outline with an Ink +,
/// like the overview's Add page, a thumbnail wide.
class SidebarAddPage extends StatelessWidget {
  const SidebarAddPage({
    super.key,
    required this.onTap,
    required this.onLongPress,
    this.bottom = 0,
  });

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// System inset below (the gesture bar).
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        SidebarMetrics.side,
        SidebarMetrics.gap + Gaps.sm,
        SidebarMetrics.side,
        Gaps.lg + bottom,
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          side: BorderSide(color: scheme.outline),
        ),
        child: ContextMenuKeys(
          onMenu: onLongPress,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.sm),
            onTap: onTap,
            onLongPress: onLongPress,
            onSecondaryTap: onLongPress,
            child: SizedBox(
              height: Targets.barHit(context) + Gaps.lg,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Symbols.add_sharp, size: Glyphs.bar, color: scheme.onSurface),
                  const SizedBox(width: Gaps.xs),
                  Flexible(
                    child: Text(
                      'Add page',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
