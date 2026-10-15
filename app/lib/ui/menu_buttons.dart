import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'menus.dart';
import 'staggered_build.dart';

/// An icon button that opens a menu of [items] below itself
/// ([showMenuBelow]); the shared replacement for [PopupMenuButton].
class MenuIconButton<T> extends StatelessWidget {
  const MenuIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.items,
    required this.onSelected,
    this.staggered = false,
  });

  final Widget icon;
  final String tooltip;

  /// Built when the menu opens, so it reflects the current state.
  final List<PopupMenuEntry<T>> Function() items;
  final ValueChanged<T> onSelected;

  /// Whether the button is completed a little later ([StaggeredBuild]):
  /// for one on every item of a long grid (an IconButton with its tooltip
  /// is costly to build). Until then the glyph stands where it will be and
  /// opens the menu too.
  final bool staggered;

  Future<void> _open(BuildContext context) async {
    final value = await showMenuBelow<T>(context, items: items());
    if (value != null) onSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    final button = IconButton(tooltip: tooltip, icon: icon, onPressed: () => _open(context));
    if (!staggered) return button;
    return StaggeredBuild(
      placeholder: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _open(context),
          child: SizedBox.square(
            dimension: switch (Theme.of(context).materialTapTargetSize) {
              MaterialTapTargetSize.padded => kMinInteractiveDimension,
              MaterialTapTargetSize.shrinkWrap => Targets.bar,
            },
            child: Center(child: icon),
          ),
        ),
      ),
      child: button,
    );
  }
}

/// Any [child] (a label with a ▾, a value) that opens a menu of [items]
/// below itself ([showMenuBelow]); [MenuIconButton] for an icon.
class MenuButton<T> extends StatelessWidget {
  const MenuButton({
    super.key,
    required this.child,
    required this.tooltip,
    required this.items,
    required this.onSelected,
  });

  final Widget child;
  final String tooltip;

  /// Built when the menu opens, so it reflects the current state.
  final List<PopupMenuEntry<T>> Function() items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      borderRadius: BorderRadius.circular(Radii.xs),
      onTap: () async {
        final value = await showMenuBelow<T>(context, items: items());
        if (value != null) onSelected(value);
      },
      child: child,
    ),
  );
}
